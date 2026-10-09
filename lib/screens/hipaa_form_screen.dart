import 'dart:convert';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
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

  // One line per medication or supplement for the signed form, including
  // serving size and ingredients for supplements.
  String _medicationSummary(Medication m, AppStrings strings) {
    final parts = <String>[
      m.name,
      if (m.dose.isNotEmpty) m.dose,
      if (m.frequency.isNotEmpty) m.frequency,
      if (m.servingSize.isNotEmpty) "${strings.servingLabel}: ${m.servingSize}",
      if (m.activeIngredients.isNotEmpty)
        "${strings.supplementFactsLabel}: ${m.activeIngredients.join(", ")}",
      if (m.otherIngredients.isNotEmpty)
        "${strings.otherIngredientsLabel}: ${m.otherIngredients.join(", ")}",
    ].where((part) => part.trim().isNotEmpty).toList();
    return parts.join(" - ");
  }

  // The built-in PDF font cannot draw "•" or "—"; without this the bullets
  // and dashes silently disappear from the signed PDF.
  String _pdfSafe(String text) => text
      .replaceAll('\u2022', '-')
      .replaceAll('\u2014', '-')
      .replaceAll('\u2013', '-');

  // English copy sent to the agent when the client signed in Spanish.
  static const String _englishReferenceNotice =
      'ENGLISH TRANSLATION FOR AGENT REFERENCE ONLY. This is not the signed '
      'document. The client read and signed the Spanish version (attached), '
      'which is the official record.';

  String clean(String? value) {
    if (value == null) return "";

    String s = value
        .replaceAll(RegExp(r'[\r\n]+'), ' ') // remove line breaks
        .replaceAll('"', '""') // escape quotes
        .trim();

    return '"$s"'; // 🔥 wrap everything in quotes
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

    // 🔥 Medications field
    const en = AppStrings('en');
    final medsStr = p.meds.map((m) => _medicationSummary(m, en)).join("; ");

    // 🔥 Doctors field
    final docsStr = p.doctors
        .map((d) =>
            "${d.name}${d.specialty.isNotEmpty ? " (${d.specialty})" : ""}")
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
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).signAuthorization),
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
            child: Text(AppStrings.of(context).clear),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (_sigCtrl.isEmpty) return;
              Navigator.pop(context);
              _saveAndSend();
            },
            child: Text(AppStrings.of(context).submit),
          ),
        ],
      ),
    );
  }

  Future<void> _startSignatureFlow() async {
    final readyToSign = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VitaLinkConfirmDialog(
        title: AppStrings.of(context).almostReady,
        message: AppStrings.of(context).confirmMedsDoctorsBeforeSigning,
        secondaryLabel: AppStrings.of(context).letMeUpdateFirst,
        primaryLabel: AppStrings.of(context).everythingLooksGood,
        onSecondary: () => Navigator.pop(context, false),
        onPrimary: () => Navigator.pop(context, true),
      ),
    );

    if (!mounted) return;

    if (readyToSign == true) {
      await _openSignaturePopup();
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VitaLinkNoticeDialog(
        title: AppStrings.of(context).noProblem,
        message: AppStrings.of(context).reviewThenComeBack,
        buttonLabel: AppStrings.of(context).reviewMyInfo,
        onPressed: () => Navigator.pop(context),
      ),
    );

    if (!mounted) return;

    Navigator.pushReplacementNamed(context, '/menu');
  }

  pw.Document _buildAuthorizationPdf({
    required AppStrings strings,
    required String signedOn,
    pw.MemoryImage? signature,
    String? notice,
  }) {
    final pdf = pw.Document();
    final meds = _profile!.meds;
    final doctors = _profile!.doctors;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          if (notice != null) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.5)),
              child: pw.Text(
                notice,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 12),
          ],
          pw.Text(
            strings.hipaaSoaAuthorization,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text(_pdfSafe(strings.hipaaAuthorizationText)),
          pw.SizedBox(height: 18),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Text(
            strings.userInfoShared,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Text(strings.medications,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (meds.isEmpty)
            pw.Text(strings.noneListed)
          else
            ...meds.map(
              (m) => pw.Bullet(text: _pdfSafe(_medicationSummary(m, strings))),
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
                text: _pdfSafe(
                  "${d.name}${d.specialty.isNotEmpty ? " - ${d.specialty}" : ""}${d.phone.isNotEmpty ? " - ${d.phone}" : ""}",
                ),
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
          if (signature != null)
            pw.Row(children: [
              pw.Text(strings.signature),
              pw.Container(width: 150, height: 60, child: pw.Image(signature)),
            ])
          else
            pw.Text(
              'Signed electronically by the client on the Spanish original '
              '(see the attached signed document).',
              style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
            ),
          pw.SizedBox(height: 8),
          pw.Text("${strings.date}: $signedOn"),
        ],
      ),
    );
    return pdf;
  }

  Future<void> _saveAndSend() async {
    if (_sigCtrl.isEmpty || _profile == null) return;

    if (_agentEmail == null || _agentEmail!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ ${AppStrings.of(context).noAgentLinked}")),
      );
      return;
    }

    // Read the language before any await; it decides the signed PDF.
    final strings = AppStrings.of(context);
    final meds = _profile!.meds;
    final doctors = _profile!.doctors;

    setState(() => _saving = true);

    try {
      final sigBytes = await _sigCtrl.toPngBytes();
      if (sigBytes == null || sigBytes.isEmpty) {
        throw Exception(AppStrings.current().signatureImageMissing);
      }

      final signedInSpanish = strings.languageCode == 'es';
      final signedOn = DateTime.now().toLocal().toString().split(' ')[0];

      // The signed original is in the language the client read and signed.
      final signedPdf = _buildAuthorizationPdf(
        strings: strings,
        signature: pw.MemoryImage(sigBytes),
        signedOn: signedOn,
      );

      final dir = await getTemporaryDirectory();
      final pdfFile = File(
        signedInSpanish
            ? "${dir.path}/HIPAA_SOA_Authorization_Signed_Spanish.pdf"
            : "${dir.path}/HIPAA_SOA_Authorization.pdf",
      );
      await pdfFile.writeAsBytes(await signedPdf.save());

      // Spanish signers: the agent also gets an English reference copy. It
      // has no signature image and says it is not the signed document.
      String? englishReferenceBase64;
      if (signedInSpanish) {
        final englishPdf = _buildAuthorizationPdf(
          strings: const AppStrings('en'),
          signedOn: signedOn,
          notice: _englishReferenceNotice,
        );
        englishReferenceBase64 = base64Encode(await englishPdf.save());
      }

      final csvFile = await _buildCsv(_profile!);
      final store = SecureStore();
      final userEmail = await store.getString('userEmail') ?? "";
      final userId = await store.getString('userId') ?? "";
      final sessionToken = await store.getString('userSessionToken') ?? "";
      final signedAt = DateTime.now().toIso8601String();
      final reviewedAt = signedAt;
      final hipaaSoaPdfBase64 = base64Encode(await pdfFile.readAsBytes());
      final vitalinkCsvBase64 = base64Encode(await csvFile.readAsBytes());

      final resp = await http
          .post(
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
                        "itemType": m.itemType,
                        "servingSize": m.servingSize,
                        "activeIngredients": m.activeIngredients,
                        "otherIngredients": m.otherIngredients,
                      })
                  .toList(),
              "providers": doctors
                  .map((d) => {
                        "name": d.name,
                        "specialty": d.specialty,
                        "phone": d.phone,
                      })
                  .toList(),
              // The signed original stays first: the server files the first
              // "HIPAA" attachment in the CRM.
              "attachments": [
                {
                  "name": signedInSpanish
                      ? "HIPAA_SOA_Authorization_Signed_Spanish.pdf"
                      : "HIPAA_SOA_Authorization.pdf",
                  "content": hipaaSoaPdfBase64,
                },
                if (englishReferenceBase64 != null)
                  {
                    "name": "English_Translation_For_Agent_Reference.pdf",
                    "content": englishReferenceBase64,
                  },
                {
                  "name": "vitalink_user_info.csv",
                  "content": vitalinkCsvBase64,
                }
              ],
              "signed_language": strings.languageCode,
            }),
          )
          .timeout(const Duration(seconds: 30));

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
            title: Text(AppStrings.of(context).sentSuccessfully),
            content: Text(
              AppStrings.of(context).hipaaSentToAgent,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.of(context).ok),
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
      appBar: AppBar(title: Text(AppStrings.of(context).hipaaSoaAuthorization)),
      body: Stack(
        children: [
          ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                AppStrings.of(context).hipaaAuthorizationText,
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
                      AppStrings.of(context).acknowledgeAgentDescription,
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canSubmit ? _startSignatureFlow : null,
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
                    AppStrings.of(context).signSendMyInformation,
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
