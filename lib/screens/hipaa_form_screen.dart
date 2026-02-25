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
import '../services/api_service.dart';
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

  String? _agentEmail;
  String? _agentName;
  String? _agentPhone;

  static const String _authorizationText = """
HIPAA AUTHORIZATION & MEDICARE SCOPE OF APPOINTMENT

By signing below, I authorize my licensed insurance agent and/or affiliated agency to access, receive, and use ONLY the following information for the purpose of assisting me with Medicare plan education and enrollment:

• My listed medications
• My listed physicians / healthcare providers

No other medical records, diagnoses, treatment notes, financial data, or unrelated personal information will be shared through this authorization.

I understand:

• This authorization is voluntary.
• I may refuse to sign without affecting my eligibility, treatment, or benefits.
• I may revoke this authorization at any time in writing.
• Revocation will not apply to information already disclosed.
• Information disclosed may be subject to redisclosure and may no longer be protected by federal privacy regulations.
• This authorization expires one (1) year from the date signed unless revoked earlier.

MEDICARE SCOPE OF APPOINTMENT (CMS Required)

I agree to discuss the following Medicare product types with my licensed agent:

• Medicare Advantage (Part C)
• Prescription Drug Plans (Part D)
• Medicare Supplement (Medigap)
• Dental / Vision / Hearing
• Hospital Indemnity and related products

I understand:

• I am not required to enroll in any plan.
• The agent may only discuss the product types listed above.
• Signing does not obligate me to enroll.
• This Scope of Appointment remains valid for twelve (12) months unless revoked.
""";

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

    String? agentEmail;
    String? agentName;
    String? agentPhone;

    final userEmail = await store.getString('userEmail');

    if (userEmail != null && userEmail.isNotEmpty) {
      final res = await ApiService.getUserAgent(userEmail);
      if (res["success"] == true && res["agent"] != null) {
        final agent = res["agent"];
        agentEmail = agent["email"];
        agentName = agent["name"];
        agentPhone = agent["phone"];
      }
    }

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

    if (_agentEmail == null || _agentEmail!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ No agent is linked to this account.")),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final sigBytes = await _sigCtrl.toPngBytes();
      if (sigBytes == null || sigBytes.isEmpty) {
        throw Exception("Signature image missing");
      }

      final pdf = pw.Document();
      final sigImg = pw.MemoryImage(sigBytes);

      final meds = _profile!.meds;
      final doctors = _profile!.doctors;

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
            pw.Text(_authorizationText),
            pw.SizedBox(height: 18),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(
              "User Information Shared (Per Authorization)",
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text("Medications",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (meds.isEmpty)
              pw.Text("None listed.")
            else
              ...meds.map(
                (m) => pw.Bullet(
                  text:
                      "${m.name}${m.dose != null ? " — ${m.dose}" : ""}${m.frequency != null ? " — ${m.frequency}" : ""}",
                ),
              ),
            pw.SizedBox(height: 12),
            pw.Text("Physicians / Healthcare Providers",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (doctors.isEmpty)
              pw.Text("None listed.")
            else
              ...doctors.map(
                (d) => pw.Bullet(
                  text:
                      "${d.name}${d.specialty != null ? " — ${d.specialty}" : ""}${d.phone != null ? " — ${d.phone}" : ""}",
                ),
              ),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 14),
            pw.Text("Recipient (Agent):",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(
                "${_agentName ?? ''}\n${_agentEmail ?? ''}\n${_agentPhone ?? ''}"),
            pw.SizedBox(height: 24),
            pw.Row(children: [
              pw.Text("Signature: "),
              pw.Container(
                width: 150,
                height: 60,
                child: pw.Image(sigImg),
              ),
            ]),
            pw.SizedBox(height: 8),
            pw.Text("Date: ${DateTime.now().toLocal().toString().split(' ')[0]}"),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final pdfFile =
          File("${dir.path}/HIPAA_SOA_Authorization.pdf");
      await pdfFile.writeAsBytes(await pdf.save());

      final csvFile = await _buildCsv(_profile!);
      final store = SecureStore();
      final userEmail = await store.getString('userEmail') ?? "";

      final resp = await http.post(
        Uri.parse(
          "https://vitalink-app.netlify.app/.netlify/functions/send_form_email",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "agent": {
            "name": _agentName ?? "",
            "email": _agentEmail,
            "phone": _agentPhone ?? ""
          },
          "user": _profile!.fullName ?? "",
          "user_email": userEmail,
          "user_phone": "",
          "user_dob": _profile!.dob ?? "",
          "medications": meds.map((m) => {
                "name": m.name,
                "dose": m.dose,
                "frequency": m.frequency,
              }).toList(),
          "providers": doctors.map((d) => {
                "name": d.name,
                "specialty": d.specialty,
                "phone": d.phone,
              }).toList(),
          "attachments": [
            {
              "name": "HIPAA_SOA_Authorization.pdf",
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

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Sent Successfully"),
            content: const Text(
              "Your HIPAA & SOA authorization has been sent to your agent.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              )
            ],
          ),
        );
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
                _authorizationText,
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
                      "I acknowledge and authorize my agent as described above.",
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