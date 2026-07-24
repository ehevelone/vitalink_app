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
import '../l10n/app_strings.dart';

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

    return '"$s"'; // Ã°Å¸â€Â¥ wrap everything in quotes
  }

  bool _saving = false;
  bool _acknowledged = false;
  bool _canScroll = false;

  Profile? _profile;

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

    // Ã°Å¸â€Â¥ Medications field
    final medsStr = p.meds
        .map((m) =>
            "${m.name}${m.dose.isNotEmpty ? " (${m.dose})" : ""}${m.frequency.isNotEmpty ? " ${m.frequency}" : ""}")
        .join("; ");

    // Ã°Å¸â€Â¥ Doctors field
    final docsStr = p.doctors
        .map((d) =>
            "${d.name}${d.specialty.isNotEmpty ? " (${d.specialty})" : ""}")
        .join("; ");

    // Ã¢Å“â€¦ HEADER
    buffer.writeln(
        "First Name,Last Name,DOB,Address,City,State,Zip Code,Phone,Email,Medications,Doctors,Notes,Source");

    // Ã¢Å“â€¦ SINGLE ROW
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

  List<Map<String, String>> _pharmacyList(Profile p) {
    final seen = <String>{};
    final pharmacies = <Map<String, String>>[];

    for (final med in p.meds) {
      final text = med.prescriber.trim();

      if (text.isEmpty || seen.contains(text.toLowerCase())) {
        continue;
      }

      seen.add(text.toLowerCase());

      final lines = text
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      pharmacies.add({
        "name": lines.isNotEmpty ? lines.first : text,
        "phone": lines.length > 1 ? lines.sublist(1).join(" ") : "",
      });
    }

    return pharmacies;
  }

  Future<void> _openSignaturePopup() async {
    final strings = AppStrings.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(strings.signAuthorization),
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
            child: Text(strings.clear),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (_sigCtrl.isEmpty) return;
              Navigator.pop(context);
              _saveAndSend();
            },
            child: Text(strings.submit),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndSend() async {
    if (_sigCtrl.isEmpty || _profile == null) return;
    final strings = AppStrings.of(context);

    if (_agentEmail == null || _agentEmail!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.noAgentLinked)),
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
              strings.hipaaSoaAuthorization,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(strings.hipaaAuthorizationText),
            pw.SizedBox(height: 18),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(
              strings.userInfoShared,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(strings.medications,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (meds.isEmpty)
              pw.Text(strings.noneListed)
            else
              ...meds.map(
                (m) => pw.Bullet(
                  text:
                      "${m.name}${m.dose.isNotEmpty ? " Ã¢â‚¬â€ ${m.dose}" : ""}${m.frequency.isNotEmpty ? " Ã¢â‚¬â€ ${m.frequency}" : ""}",
                ),
              ),
            pw.SizedBox(height: 12),
            pw.Text(strings.physiciansProviders,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (doctors.isEmpty)
              pw.Text(strings.noneListed)
            else
              ...doctors.map(
                (d) => pw.Bullet(
                  text:
                      "${d.name}${d.specialty.isNotEmpty ? " Ã¢â‚¬â€ ${d.specialty}" : ""}${d.phone.isNotEmpty ? " Ã¢â‚¬â€ ${d.phone}" : ""}",
                ),
              ),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 14),
            pw.Text(strings.recipientAgent,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(
                "${_agentName ?? ''}\n${_agentEmail ?? ''}\n${_agentPhone ?? ''}"),
            pw.SizedBox(height: 24),
            pw.Row(children: [
              pw.Text(strings.signature),
              pw.Container(
                width: 150,
                height: 60,
                child: pw.Image(sigImg),
              ),
            ]),
            pw.SizedBox(height: 8),
            pw.Text(
                "${strings.date}: ${DateTime.now().toLocal().toString().split(' ')[0]}"),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final pdfFile = File("${dir.path}/HIPAA_SOA_Authorization.pdf");
      await pdfFile.writeAsBytes(await pdf.save());

      final csvFile = await _buildCsv(_profile!);
      final store = SecureStore();
      final userEmail = await store.getString('userEmail') ?? "";
      final userId = await store.getString('userId') ?? "";
      final signedAt = DateTime.now().toIso8601String();
      final hipaaSoaPdfBase64 = base64Encode(await pdfFile.readAsBytes());
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
          "app_profile_id": _profile!.id,
          "signed_at": signedAt,
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
                  })
              .toList(),
          "attachments": [
            {
              "name": "HIPAA_SOA_Authorization.pdf",
              "content": hipaaSoaPdfBase64,
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

// Ã¢Å“â€¦ Mark reviewed so user stops getting notifications this cycle
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
            title: Text(strings.sentSuccessfully),
            content: Text(strings.hipaaSentToAgent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(strings.ok),
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
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.hipaaSoaAuthorization)),
      body: Stack(
        children: [
          ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                strings.hipaaAuthorizationText,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 300),
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
                  Expanded(
                    child: Text(
                      strings.acknowledgeAgentDescription,
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canSubmit ? _openSignaturePopup : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.send),
                  label: Text(
                    strings.signSendMyInformation,
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
