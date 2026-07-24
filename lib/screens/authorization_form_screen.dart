import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:http/http.dart' as http;
import '../services/secure_store.dart';

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

  String? _agentName, _agentEmail, _agentPhone;
  List<dynamic> _meds = [], _doctors = [];

  @override
  void initState() {
    super.initState();
    _loadData();

    // listen for scroll-to-bottom
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
    final agentName = await store.getString("agentName") ?? "Your Agent";
    final agentEmail = await store.getString("agentEmail") ?? "";
    final agentPhone = await store.getString("agentPhone") ?? "";
    final meds = jsonDecode(await store.getString("medsList") ?? "[]");
    final docs = jsonDecode(await store.getString("doctorsList") ?? "[]");

    if (!mounted) return;
    setState(() {
      _agentName = agentName;
      _agentEmail = agentEmail;
      _agentPhone = agentPhone;
      _meds = meds;
      _doctors = docs;
    });
  }

  Future<void> _openSignaturePopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
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
    if (_sigCtrl.isEmpty) return;

    setState(() => _saving = true);

    try {
      final sigBytes = await _sigCtrl.toPngBytes();
      final tempDir = await getTemporaryDirectory();
      final sigFile = File("${tempDir.path}/signature.png");
      await sigFile.writeAsBytes(sigBytes!);

      final pdf = pw.Document();
      final sigImg = pw.MemoryImage(sigBytes);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Text("HIPAA & SOA Authorization",
                style:
                    pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.Text(
              "I understand that by signing below, I authorize my licensed insurance agent to access, discuss, and use my Protected Health Information (PHI) "
              "for the purpose of helping me understand and enroll in Medicare health plans.\n\n"
              "This authorization is voluntary and will not affect my eligibility for treatment or benefits. "
              "I may revoke this authorization at any time by submitting a written request. "
              "Unless I revoke it sooner, this authorization will expire one (1) year from the date of my signature.\n\n"
              "This document also serves as a combined Scope of Appointment, allowing discussion of Medicare Advantage (MA), Prescription Drug (PDP), "
              "and Medicare Supplement (Medigap) plan options.\n\n"
              "I acknowledge that I have read and understand this authorization.",
            ),
            pw.SizedBox(height: 20),
            pw.Text("Recipient (Agent):",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(
                "${_agentName ?? ''}\n${_agentEmail ?? ''}\n${_agentPhone ?? ''}"),
            pw.SizedBox(height: 24),
            pw.Row(children: [
              pw.Text("Signature:  "),
              pw.Container(width: 150, height: 60, child: pw.Image(sigImg)),
            ]),
            pw.SizedBox(height: 8),
            pw.Text(
                "Date: ${DateTime.now().toLocal().toString().split(' ')[0]}"),
            pw.SizedBox(height: 8),
            pw.Text(
                "Expires: ${DateTime.now().add(const Duration(days: 365)).toLocal().toString().split(' ')[0]}"),
            pw.NewPage(),
            pw.Text("Medication List",
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            if (_meds.isEmpty) pw.Text("No medications on file."),
            if (_meds.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headers: ["Medication", "Dosage", "Frequency"],
                data: _meds
                    .map((m) => [
                          m["name"] ?? "",
                          m["dosage"] ?? "",
                          m["frequency"] ?? "",
                        ])
                    .toList(),
              ),
            pw.SizedBox(height: 16),
            pw.Text("Doctors List",
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            if (_doctors.isEmpty) pw.Text("No doctors on file."),
            if (_doctors.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headers: ["Name", "Specialty", "Phone"],
                data: _doctors
                    .map((d) => [
                          d["name"] ?? "",
                          d["specialty"] ?? "",
                          d["phone"] ?? "",
                        ])
                    .toList(),
              ),
          ],
        ),
      );

      final pdfFile = File("${tempDir.path}/HIPAA_SOA_Authorization.pdf");
      await pdfFile.writeAsBytes(await pdf.save());

      // Send email
      final payload = {
        "agentEmail": _agentEmail,
        "subject": "Client HIPAA & SOA Authorization",
        "body":
            "Attached is the signed HIPAA & SOA Authorization and client’s medication and doctor details.",
        "attachments": [
          {"path": pdfFile.path, "name": "HIPAA_SOA_Authorization.pdf"}
        ]
      };

      final resp = await http.post(
        Uri.parse(
            "https://vitalink-app.netlify.app/.netlify/functions/send_form_email"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (resp.statusCode == 200) {
        if (!mounted) return;

        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Success"),
            content: const Text("Authorization email sent successfully ✅"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );

        // Redirect by role
        final store = SecureStore();
        final role = await store.getString('role');
        if (!mounted) return;
        if (role == 'agent') {
          Navigator.pushReplacementNamed(context, '/my_agent_agent');
        } else {
          Navigator.pushReplacementNamed(context, '/my_agent_user');
        }
      } else {
        throw Exception("Failed to send email: ${resp.body}");
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Error"),
          content: Text("❌ Failed to send authorization: $e"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
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
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: canSubmit ? _openSignaturePopup : null,
                icon: const Icon(Icons.send),
                label: const Text("Sign & Send My Information"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
