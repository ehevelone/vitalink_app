import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:http/http.dart' as http;

import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../models.dart';

class HipaaFormScreen extends StatefulWidget {
  const HipaaFormScreen({super.key});

  @override
  State<HipaaFormScreen> createState() => _HipaaFormScreenState();
}

class _HipaaFormScreenState extends State<HipaaFormScreen> {
  final SignatureController _sigCtrl = SignatureController(penStrokeWidth: 3);
  final ScrollController _scrollCtrl = ScrollController();

  bool _saving = false;
  bool _acknowledged = false;
  bool _canScroll = false;

  Profile? _profile;

  // ✅ AGENT COMES FROM SECURE STORE
  String? _agentEmail;
  String? _agentName;
  String? _agentPhone;

  @override
  void initState() {
    super.initState();
    _loadData();

    _scrollCtrl.addListener(() {
      final atBottom =
          _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent &&
              !_scrollCtrl.position.outOfRange;
      if (atBottom && !_canScroll) {
        setState(() => _canScroll = true);
      }
    });
  }

  Future<void> _loadData() async {
    final store = SecureStore();
    final repo = DataRepository(store);

    final p = await repo.loadProfile();

    final agentEmail = await store.getString('agentEmail');
    final agentName = await store.getString('agentName');
    final agentPhone = await store.getString('agentPhone');

    if (!mounted) return;

    setState(() {
      _profile = p;
      _agentEmail = agentEmail;
      _agentName = agentName;
      _agentPhone = agentPhone;
    });
  }

  Future<File> _buildCsv(Profile p) async {
    final buffer = StringBuffer();
    buffer.writeln("TYPE,NAME,DETAILS");

    for (final m in p.meds) {
      buffer.writeln(
        "Medication,${m.name},${m.dose ?? ''} ${m.frequency ?? ''}",
      );
    }

    for (final d in p.doctors) {
      buffer.writeln(
        "Doctor,${d.name},${d.specialty ?? ''} ${d.phone ?? ''}",
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/vitalink_user_info.csv");
    await file.writeAsString(buffer.toString());
    return file;
  }

  Future<void> _openSignaturePopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Sign Authorization"),
        content: SizedBox(
          height: 200,
          width: 300,
          child: Signature(
            controller: _sigCtrl,
            backgroundColor: Colors.grey[200]!,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _sigCtrl.clear(),
            child: const Text("Clear"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (_sigCtrl.isEmpty) return;
              Navigator.pop(context);
              _saveAndSend();
            },
            child: const Text("Submit"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndSend() async {
    if (_sigCtrl.isEmpty || _profile == null) return;

    final agentEmail = _agentEmail;
    final agentName = _agentName;
    final agentPhone = _agentPhone;

    if (agentEmail == null || agentEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ No agent is linked to this account.")),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final sigBytes = await _sigCtrl.toPngBytes();

      // 🚨 HARD FAIL IF SIGNATURE MISSING (THIS WAS THE BUG)
      if (sigBytes == null || sigBytes.isEmpty) {
        throw Exception("Signature image missing");
      }

      final pdf = pw.Document();
      final sigImg = pw.MemoryImage(sigBytes);

      final timestamp = DateTime.now()
          .toIso8601String()
          .split(".")
          .first
          .replaceAll(":", "-");

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Text(
              "HIPAA & SOA Authorization",
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              "I understand that by signing below, I authorize my licensed insurance agent to access, discuss, and use my Protected Health Information (PHI) "
              "for the purpose of helping me understand and enroll in Medicare health plans.\n\n"
              "This authorization is voluntary and will not affect my eligibility for treatment or benefits. "
              "I may revoke this authorization at any time by submitting a written request. "
              "Unless I revoke it sooner, this authorization will expire one (1) year from the date of my signature.\n\n"
              "This document also serves as a combined Scope of Appointment, allowing discussion of Medicare Advantage (MA), Prescription Drug (PDP), "
              "and Medicare Supplement (Medigap) plan options.\n\n"
              "Discussion Topics (Scope of Appointment):\n"
              "- Medicare Advantage (Part C) & Cost Plans\n"
              "- Prescription Drug Plan (Part D)\n"
              "- Medicare Supplement (Medigap) Plans\n"
              "- Dental / Vision / Hearing Products\n"
              "- Hospital Indemnity Products\n\n"
              "I acknowledge that I have read and understand this authorization.",
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              "Recipient (Agent):",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              "${agentName ?? ''}\n$agentEmail\n${agentPhone ?? ''}",
            ),
            pw.SizedBox(height: 24),
            pw.Row(
              children: [
                pw.Text("Signature: "),
                pw.Container(
                  width: 150,
                  height: 60,
                  child: pw.Image(sigImg),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text("Date: ${DateTime.now().toLocal().toString().split(' ')[0]}"),
            pw.Text(
              "Expires: ${DateTime.now().add(const Duration(days: 365)).toLocal().toString().split(' ')[0]}",
            ),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final pdfFile =
          File("${dir.path}/HIPAA_SOA_Authorization_$timestamp.pdf");
      await pdfFile.writeAsBytes(await pdf.save());

      final csvFile = await _buildCsv(_profile!);

      final resp = await http.post(
        Uri.parse(
          "https://vitalink-app.netlify.app/.netlify/functions/send_form_email",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "agent": {
            "name": agentName ?? "",
            "email": agentEmail,
            "phone": agentPhone ?? ""
          },
          "user": _profile!.fullName ?? "",
          "attachments": [
            {
              "name": pdfFile.path.split('/').last,
              "content": base64Encode(await pdfFile.readAsBytes()),
            },
            {
              "name": "vitalink_user_info.csv",
              "content": base64Encode(await csvFile.readAsBytes()),
            }
          ]
        }),
      );

      if (resp.statusCode != 200) {
        throw Exception(resp.body);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _acknowledged && _canScroll && !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text("HIPAA & SOA Authorization")),
      body: Stack(
        children: [
          ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: const [
              Text(
                "Authorization to Disclose Health Information\n",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                "I understand that by signing below, I authorize my licensed insurance agent to access, discuss, and use my Protected Health Information (PHI) "
                "for the purpose of helping me understand and enroll in Medicare health plans.\n\n"
                "This authorization is voluntary and will not affect my eligibility for treatment or benefits. "
                "I may revoke this authorization at any time by submitting a written request. "
                "Unless I revoke it sooner, this authorization will expire one (1) year from the date of my signature.\n\n"
                "This document also serves as a combined Scope of Appointment, allowing discussion of Medicare Advantage (MA), Prescription Drug (PDP), "
                "and Medicare Supplement (Medigap) plan options.\n\n"
                "Discussion Topics (Scope of Appointment):\n"
                "- Medicare Advantage (Part C) & Cost Plans\n"
                "- Prescription Drug Plan (Part D)\n"
                "- Medicare Supplement (Medigap) Plans\n"
                "- Dental / Vision / Hearing Products\n"
                "- Hospital Indemnity Products\n\n"
                "I acknowledge that I have read and understand this authorization.",
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              SizedBox(height: 300),
            ],
          ),
          if (_saving)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _acknowledged,
                    onChanged: (v) =>
                        setState(() => _acknowledged = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      "I acknowledge and authorize my agent to discuss my Medicare information.",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: canSubmit ? _openSignaturePopup : null,
                icon: const Icon(Icons.send),
                label: const Text("Sign & Send My Information"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
