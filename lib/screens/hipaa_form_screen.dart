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
import '../services/app_state.dart';

class HipaaFormScreen extends StatefulWidget {
  const HipaaFormScreen({super.key});

  @override
  State<HipaaFormScreen> createState() => _HipaaFormScreenState();
}

class _HipaaFormScreenState extends State<HipaaFormScreen> {
  final SignatureController _sigCtrl = SignatureController(penStrokeWidth: 3);
  final ScrollController _scrollCtrl = ScrollController();

  String clean(String? value) {
    if (value == null) return "";

    String s = value
        .replaceAll(RegExp(r'[\r\n]+'), ' ') // remove line breaks
        .replaceAll('"', '""') // escape quotes
        .trim();

    return '"$s"'; // 🔥 wrap everything in quotes
  }

  bool _saving = false;
  bool _hipaaAcknowledged = false;
  bool _soaAcknowledged = false;
  bool _canScroll = false;
  int _step = 0;
  final Set<String> _selectedProducts = {};

  Profile? _profile;

  String? _agentEmail;
  String? _agentName;
  String? _agentPhone;

  static const String _hipaaText = """
HEALTH INFORMATION AUTHORIZATION

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
""";

  static const String _soaText = """
MEDICARE SCOPE OF APPOINTMENT

Select only the product types you want to discuss with your licensed agent. The agent may discuss only the product types you select.

I understand:

• I am not required to enroll in any plan.
• My current or future Medicare enrollment status will not be affected by signing.
• Signing will not automatically enroll me in any plan.
• If I want to discuss another product type later, a new Scope of Appointment may be needed.
""";

  static const List<String> _products = [
    'Medicare Advantage (Part C)',
    'Prescription Drug Plans (Part D)',
    'Medicare Supplement (Medigap)',
    'Dental / Vision / Hearing',
    'Hospital Indemnity and related products',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _sigCtrl.addListener(() {
      if (mounted && _step == 3) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _confirmInformationFirst();
    });

    _scrollCtrl.addListener(() {
      final atBottom =
          _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent &&
              !_scrollCtrl.position.outOfRange;
      if (atBottom && !_canScroll && (_step == 1 || _step == 2)) {
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

    final userEmail = await AppState.getEmail();

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

    final userEmail = await SecureStore().getString('userEmail') ?? "";

    final parts = p.fullName.trim().split(' ');
    final firstName = parts.isNotEmpty ? parts.first : "";
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : "";

    // 🔥 Medications field
    final medsStr = p.meds
        .map((m) =>
            "${m.name}${m.dose.isNotEmpty ? " (${m.dose})" : ""}${m.frequency.isNotEmpty ? " ${m.frequency}" : ""}${m.prescriber.isNotEmpty ? " | Pharmacy: ${m.prescriber}" : ""}${m.pharmacyVerificationStatus == 'verified' && m.pharmacyNpi != null ? " | Pharmacy NPI: ${m.pharmacyNpi} (verified)" : ""}")
        .join("; ");

    // 🔥 Doctors field
    final docsStr = p.doctors
        .map((d) =>
            "${d.name}${d.specialty.isNotEmpty ? " (${d.specialty})" : ""}${d.isPrimaryCareProvider ? " [Primary Care]" : ""}${d.verificationStatus == 'verified' && d.npi != null ? " [NPI: ${d.npi} verified]" : ""}")
        .join("; ");

    // ✅ HEADER
    buffer.writeln(
        "First Name,Last Name,DOB,Address,City,State,Zip Code,Phone,Email,Medications,Doctors,Notes,Source");

    // ✅ SINGLE ROW
    buffer.writeln("${clean(firstName)},"
        "${clean(lastName)},"
        "${clean(p.dob)},"
        "${clean(p.address)},"
        "${clean(p.city)},"
        "${clean(p.state)},"
        "${clean(p.zip)},"
        "${clean(p.userPhone)},"
        "${clean(userEmail)},"
        "${clean(medsStr)},"
        "${clean(docsStr)},"
        "${clean("VitaLink Client | Meds: $medsStr | Doctors: $docsStr")},"
        "${clean("VitaLink")}");

    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/vitalink_user_info.csv");
    await file.writeAsString(buffer.toString());
    return file;
  }

  List<Map<String, dynamic>> _pharmacyList(Profile p) {
    final pharmacies = <Map<String, dynamic>>[];

    for (final med in p.meds) {
      final text = med.prescriber.trim();

      if (text.isEmpty) continue;

      final lines = text
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      final pharmacy = <String, dynamic>{
        "name": lines.isNotEmpty ? lines.first : text,
        "phone": lines.length > 1 ? lines.sublist(1).join(" ") : "",
        if (med.pharmacyVerificationStatus == 'verified' &&
            med.pharmacyNpi != null)
          "npi": med.pharmacyNpi,
      };
      final key = text.toLowerCase();
      final existingIndex = pharmacies.indexWhere(
        (item) => item['_key'] == key,
      );

      if (existingIndex >= 0) {
        if (pharmacy['npi'] != null) {
          pharmacies[existingIndex]['npi'] = pharmacy['npi'];
        }
        continue;
      }

      pharmacy['_key'] = key;
      pharmacies.add(pharmacy);
    }

    return pharmacies
        .map((pharmacy) => Map<String, dynamic>.from(pharmacy)..remove('_key'))
        .toList();
  }

  Future<void> _confirmInformationFirst() async {
    final readyToSign = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VitaLinkConfirmDialog(
        title: "Before you begin",
        message:
            "Before signing, please confirm your medications and doctors are current. Your agent uses this to help find you the best coverage.",
        secondaryLabel: "Let me update first",
        primaryLabel: "Everything looks good",
        onSecondary: () => Navigator.pop(context, false),
        onPrimary: () => Navigator.pop(context, true),
      ),
    );

    if (!mounted) return;

    if (readyToSign == true) {
      _advanceTo(1);
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VitaLinkNoticeDialog(
        title: "No problem!",
        message:
            "Review your medications and doctors, then come back to sign when everything looks right.",
        buttonLabel: "Review my info",
        onPressed: () => Navigator.pop(context),
      ),
    );

    if (!mounted) return;

    Navigator.pushReplacementNamed(context, '/menu');
  }

  void _advanceTo(int step) {
    setState(() {
      _step = step;
      _canScroll = false;
    });
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      if (_scrollCtrl.position.maxScrollExtent <= 0) {
        setState(() => _canScroll = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _sigCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndSend() async {
    if (_sigCtrl.isEmpty || _profile == null || !_hipaaAcknowledged ||
        !_soaAcknowledged || _selectedProducts.isEmpty) {
      return;
    }

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

      final sigImg = pw.MemoryImage(sigBytes);

      final meds = _profile!.meds;
      final doctors = _profile!.doctors;

      final signedAt = DateTime.now().toUtc().toIso8601String();
      final clientEmail = await SecureStore().getString('userEmail') ?? '';
      final hipaaPdf = pw.Document();
      hipaaPdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Text(
              "Health Information Authorization",
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(_hipaaText),
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
                      "${m.name}${m.dose.isNotEmpty ? " — ${m.dose}" : ""}${m.frequency.isNotEmpty ? " — ${m.frequency}" : ""}",
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
                      "${d.name}${d.specialty.isNotEmpty ? " — ${d.specialty}" : ""}${d.isPrimaryCareProvider ? " — Primary Care" : ""}${d.phone.isNotEmpty ? " — ${d.phone}" : ""}",
                ),
              ),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 14),
            pw.Text("Recipient (Agent):",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(
                "${_agentName ?? ''}\n${_agentEmail ?? ''}\n${_agentPhone ?? ''}"),
            pw.Text("Client: ${_profile!.fullName}"),
            pw.Text("Email: $clientEmail"),
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
            pw.Text("Signed at (UTC): $signedAt"),
          ],
        ),
      );

      final soaPdf = pw.Document();
      soaPdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text('Medicare Scope of Appointment',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text(_soaText),
          pw.SizedBox(height: 16),
          pw.Text('Product types selected by the client:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ..._products.where(_selectedProducts.contains).map((p) => pw.Bullet(text: p)),
          pw.SizedBox(height: 18),
          pw.Text('Client: ${_profile!.fullName}'),
          pw.Text('Agent: ${_agentName ?? ''}'),
          pw.Text('Agent email: ${_agentEmail ?? ''}'),
          pw.Text('Agent phone: ${_agentPhone ?? ''}'),
          pw.SizedBox(height: 20),
          pw.Row(children: [
            pw.Text('Signature: '),
            pw.Container(width: 150, height: 60, child: pw.Image(sigImg)),
          ]),
          pw.Text('Signed at (UTC): $signedAt'),
        ],
      ));

      final dir = await getTemporaryDirectory();
      final hipaaFile = File("${dir.path}/Health_Information_Authorization.pdf");
      final soaFile = File("${dir.path}/Medicare_Scope_of_Appointment.pdf");
      await hipaaFile.writeAsBytes(await hipaaPdf.save());
      await soaFile.writeAsBytes(await soaPdf.save());

      final csvFile = await _buildCsv(_profile!);
      final store = SecureStore();
      final userEmail = await store.getString('userEmail') ?? "";
      final userId = await store.getString('userId') ?? "";
      final sessionToken = await store.getString('userSessionToken') ?? "";
      final reviewedAt = signedAt;
      final hipaaPdfBase64 = base64Encode(await hipaaFile.readAsBytes());
      final soaPdfBase64 = base64Encode(await soaFile.readAsBytes());
      final vitalinkCsvBase64 = base64Encode(await csvFile.readAsBytes());

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
          "user": _profile!.fullName,
          "user_email": userEmail,
          "user_phone": _profile!.userPhone,
          "user_dob": _profile!.dob ?? "",
          "user_address": _profile!.address ?? "",
          "user_city": _profile!.city ?? "",
          "user_state": _profile!.state ?? "",
          "user_zip": _profile!.zip ?? "",
          "app_user_id": userId,
          "sessionToken": sessionToken,
          "app_profile_id": _profile!.id,
          "signed_at": signedAt,
          "soa_product_types": _products.where(_selectedProducts.contains).toList(),
          "meds_reviewed_at": reviewedAt,
          "doctors_reviewed_at": reviewedAt,
          "emergency_contacts": _profile!.emergency.effectiveContacts
              .map((c) => {
                    "name": c.name,
                    "phone": c.phone,
                  })
              .toList(),
          "pharmacies": _pharmacyList(_profile!),
          "medications": meds
              .map((m) => {
                    "name": m.name,
                    "dose": m.dose,
                    "frequency": m.frequency,
                    "pharmacy": m.prescriber,
                  })
              .toList(),
          "providers": doctors
              .map((d) => {
                    "name": d.name,
                    "specialty": d.specialty,
                    "phone": d.phone,
                    "is_primary_care_provider": d.isPrimaryCareProvider,
                    if (d.verificationStatus == 'verified' && d.npi != null)
                      "npi": d.npi,
                  })
              .toList(),
          "attachments": [
            {
              "name": "Health_Information_Authorization.pdf",
              "content": hipaaPdfBase64,
            },
            {
              "name": "Medicare_Scope_of_Appointment.pdf",
              "content": soaPdfBase64,
            },
            {
              "name": "vitalink_user_info.csv",
              "content": vitalinkCsvBase64,
            }
          ]
        }),
      );

      if (resp.statusCode != 200) {
        throw Exception(resp.body);
      }

// ✅ Mark reviewed so user stops getting notifications this cycle
      try {
        final email = userEmail.trim();
        if (email.isNotEmpty) {
          await ApiService.markReviewed(email: email);
        }
      } catch (_) {}

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Sent Successfully"),
            content: const Text(
              "Your signed authorization and Scope of Appointment have been sent to your agent.",
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
    final canContinue = _step == 1
        ? _hipaaAcknowledged && _canScroll
        : _step == 2
            ? _soaAcknowledged && _selectedProducts.isNotEmpty && _canScroll
            : _step == 3 && _sigCtrl.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Authorization and SOA'),
        leading: _step > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _saving ? null : () => _advanceTo(_step - 1),
              )
            : null,
      ),
      body: Stack(
        children: [
          if (_step == 0)
            const Center(child: CircularProgressIndicator())
          else if (_step == 3)
            ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Step 3 of 3 - Signature',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Your signature will be placed on two separate documents: the Health Information Authorization and the Scope of Appointment with only your selected product types.',
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: Signature(controller: _sigCtrl, backgroundColor: Colors.white),
              ),
              TextButton(
                onPressed: () => setState(_sigCtrl.clear),
                child: const Text('Clear signature'),
              ),
            ])
          else
            ListView(
              key: ValueKey(_step),
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                Text('Step $_step of 3',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(_step == 1 ? _hipaaText : _soaText,
                    style: const TextStyle(fontSize: 16, height: 1.4)),
                if (_step == 2) ...[
                  const SizedBox(height: 18),
                  CheckboxListTile(
                    title: const Text('Select all product types'),
                    value: _selectedProducts.length == _products.length,
                    onChanged: (value) => setState(() {
                      _selectedProducts.clear();
                      if (value == true) _selectedProducts.addAll(_products);
                    }),
                  ),
                  ..._products.map((product) => CheckboxListTile(
                        title: Text(product),
                        value: _selectedProducts.contains(product),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selectedProducts.add(product);
                          } else {
                            _selectedProducts.remove(product);
                          }
                        }),
                      )),
                ],
              ],
            ),
          if (_saving)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: _step == 0 ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_step < 3)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _step == 1 ? _hipaaAcknowledged : _soaAcknowledged,
                  onChanged: !_canScroll ? null : (value) => setState(() {
                    if (_step == 1) {
                      _hipaaAcknowledged = value ?? false;
                    } else {
                      _soaAcknowledged = value ?? false;
                    }
                  }),
                  title: Text(_step == 1
                      ? 'I authorize the information sharing described in the Health Information Authorization.'
                      : 'I agree to discuss only the product types I selected in the Scope of Appointment.'),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canContinue && !_saving
                      ? () {
                          if (_step < 3) {
                            _advanceTo(_step + 1);
                          } else {
                            _saveAndSend();
                          }
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(_step == 3 ? Icons.draw : Icons.arrow_forward),
                  label: Text(
                    _step == 3 ? 'Sign both documents and send' : 'Continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VitaLinkConfirmDialog extends StatelessWidget {
  const _VitaLinkConfirmDialog({
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
  });

  final String title;
  final String message;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF78C7E7).withValues(alpha: .45),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .45),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF78C7E7).withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: Color(0xFF78C7E7),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF78C7E7),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onPrimary,
                child: Text(
                  primaryLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF78C7E7),
                  side: const BorderSide(color: Color(0xFF78C7E7)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VitaLinkNoticeDialog extends StatelessWidget {
  const _VitaLinkNoticeDialog({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF78C7E7).withValues(alpha: .45),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .45),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF78C7E7).withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.checklist,
                    color: Color(0xFF78C7E7),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF78C7E7),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onPressed,
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
