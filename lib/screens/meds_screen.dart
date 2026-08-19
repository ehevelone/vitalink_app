// lib/screens/meds_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import 'vitalink_camera_capture_screen.dart';

class MedsScreen extends StatefulWidget {
  const MedsScreen({super.key});

  @override
  State<MedsScreen> createState() => _MedsScreenState();
}

class _MedsScreenState extends State<MedsScreen> {
  static const List<String> _doctorSpecialtyOptions = [
    'Primary',
    'Cardiologist',
    'Orthopedic',
    'Neurologist',
    'Endocrinologist',
    'Pulmonologist',
    'Gastroenterologist',
    'Nephrologist',
    'Urologist',
    'Oncologist',
    'Dermatologist',
    'Psychiatrist',
    'Pain Management',
    'Other',
  ];

  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.loadProfile();
    if (!mounted) return;
    setState(() {
      _p = p;
      _loading = false;
    });
  }

  Future<void> _save() async {
    _p!.updatedAt = DateTime.now();
    await _repo.saveProfile(_p!);
    if (mounted) setState(() {});
  }

  // ----------------------------
  // NORMALIZATION HELPERS
  // ----------------------------

  String _normalizeMed(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'hcl'), '')
        .replaceAll(RegExp(r'hydrochloride'), '')
        .replaceAll(",", "")
        .replaceAll("-", " ")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();
  }

  String _normalizeName(String name) {
    final cleaned = name
        .toLowerCase()
        .replaceAll(",", " ")
        .replaceAll(RegExp(r'\b(dr|doctor|md|do|np|pa|aprn|fnp|pharmd)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();

    final parts = cleaned.split(" ")..removeWhere((p) => p.isEmpty);
    parts.sort();
    return parts.join(" ");
  }

  List<String> _doctorNameParts(String name) {
    return name
        .toLowerCase()
        .replaceAll(",", " ")
        .replaceAll(RegExp(r'\b(dr|doctor|md|do|np|pa|aprn|fnp|pharmd)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), " ")
        .trim()
        .split(" ")
      ..removeWhere((p) => p.isEmpty);
  }

  String _toLastFirstFormat(String name) {
    final cleaned =
        name.replaceAll(",", " ").replaceAll(RegExp(r'\s+'), " ").trim();

    final parts = cleaned.split(" ")..removeWhere((p) => p.isEmpty);
    if (parts.length < 2) return cleaned;

    final last = parts.last;
    final firstMiddle = parts.sublist(0, parts.length - 1).join(" ");
    return "$last, $firstMiddle";
  }

  bool _doctorExistsByNormalizedName(String docName) {
    final target = _normalizeName(docName);
    final targetParts = _doctorNameParts(docName);
    if (targetParts.isEmpty) return false;

    return _p!.doctors.any((d) {
      final existing = _normalizeName(d.name);
      if (existing == target) return true;

      final existingParts = _doctorNameParts(d.name);
      if (existingParts.isEmpty) return false;

      final overlap = targetParts
          .where(
            (targetPart) => existingParts.any(
              (existingPart) =>
                  existingPart == targetPart ||
                  existingPart.startsWith(targetPart) ||
                  targetPart.startsWith(existingPart),
            ),
          )
          .length;

      final targetHasInitialOrShortName =
          targetParts.any((part) => part.length <= 2);
      final minNeeded = targetHasInitialOrShortName ? 1 : 2;

      return overlap >= minNeeded &&
          (targetParts.length <= existingParts.length ||
              existingParts.length <= targetParts.length);
    });
  }

  Map<String, dynamic> _normalizeParsed(dynamic parsed) {
    if (parsed == null) return {};
    if (parsed is Map<String, dynamic>) {
      if (parsed.containsKey("name") ||
          parsed.containsKey("dose") ||
          parsed.containsKey("item_type")) {
        return parsed;
      }
      if (parsed.containsKey("rawText")) {
        final raw = parsed["rawText"]
            .toString()
            .replaceAll("```json", "")
            .replaceAll("```", "")
            .trim();
        try {
          return jsonDecode(raw);
        } catch (_) {
          return {};
        }
      }
    }
    return {};
  }

  String _normalizeItemType(dynamic value) {
    final type = value?.toString().toLowerCase().trim() ?? '';
    if (type == 'supplement' || type == 'otc' || type == 'unknown') {
      return type;
    }
    return 'prescription';
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[\n;]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return [];
  }

  String _joinLines(List<String> values) => values.join('\n');

  String _stripBrandMarks(String value) {
    return value
        .replaceAll(RegExp(r'(™|®|℠|©)'), '')
        .replaceAll(RegExp(r'(â„¢|Â®|â„ |Â©|&trade;|&reg;)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _stripBrandMarksFromList(List<String> values) {
    return values
        .map(_stripBrandMarks)
        .where((value) => value.isNotEmpty)
        .toList();
  }

  String _typeLabel(String itemType) {
    switch (itemType) {
      case 'supplement':
        return 'Supplement';
      case 'otc':
        return 'OTC';
      case 'unknown':
        return 'Unknown';
      default:
        return 'Prescription';
    }
  }

  String _supplementPreview(Medication m) {
    final parts = <String>[
      if (m.dose.isNotEmpty) m.dose,
      if (m.frequency.isNotEmpty) m.frequency,
      if (m.servingSize.isNotEmpty) 'Serving: ${m.servingSize}',
      if (m.activeIngredients.isNotEmpty)
        'Supplement Facts: ${m.activeIngredients.take(3).join(", ")}',
    ];
    return parts.join(' • ');
  }

  String _buildPharmacyDisplay(Map<String, dynamic> data) {
    final pharm = (data['pharmacy'] ?? "").toString().trim();
    final pharmPhone = (data['pharmacy_phone'] ?? "").toString().trim();

    if (pharm.isEmpty && pharmPhone.isEmpty) return "";

    if (pharm.isNotEmpty && pharmPhone.isNotEmpty) {
      return "$pharm\n$pharmPhone";
    }

    return pharm.isNotEmpty ? pharm : pharmPhone;
  }

  Future<String> _chooseDoctorSpecialty(String doctorName) async {
    String selected = _doctorSpecialtyOptions.first;
    final otherCtrl = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'New Doctor Found',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                doctorName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'What type of doctor is this?',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selected,
                dropdownColor: const Color(0xFF111111),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Doctor Type',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                items: _doctorSpecialtyOptions
                    .map(
                      (option) => DropdownMenuItem(
                        value: option,
                        child: Text(option),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selected = value);
                },
              ),
              if (selected == 'Other') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: otherCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Enter Doctor Type',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
              ),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () {
                final specialty =
                    selected == 'Other' ? otherCtrl.text.trim() : selected;
                Navigator.pop(context, specialty);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Type'),
            ),
          ],
        ),
      ),
    );

    otherCtrl.dispose();
    return result?.trim() ?? '';
  }

  // ----------------------------
  // ADD / EDIT DIALOG
  // ----------------------------

  Future<void> _addOrEdit({
    Medication? existing,
    int? index,
    Map<String, dynamic>? prefill,
  }) async {
    String itemType = _normalizeItemType(
      prefill?['item_type'] ?? prefill?['itemType'] ?? existing?.itemType,
    );
    final nameCtrl =
        TextEditingController(text: prefill?['name'] ?? existing?.name ?? '');
    final doseCtrl =
        TextEditingController(text: prefill?['dose'] ?? existing?.dose ?? '');
    final freqCtrl = TextEditingController(
        text: prefill?['frequency'] ?? existing?.frequency ?? '');
    final pharmacyCtrl = TextEditingController(
        text: prefill?['prescriber'] ?? existing?.prescriber ?? '');
    final servingSizeCtrl = TextEditingController(
        text: prefill?['serving_size'] ??
            prefill?['servingSize'] ??
            existing?.servingSize ??
            '');
    final activeIngredientsCtrl = TextEditingController(
      text: _joinLines(
        _stringList(prefill?['active_ingredients'] ??
            prefill?['activeIngredients'] ??
            existing?.activeIngredients),
      ),
    );
    final otherIngredientsCtrl = TextEditingController(
      text: _joinLines(
        _stringList(prefill?['other_ingredients'] ??
            prefill?['otherIngredients'] ??
            existing?.otherIngredients),
      ),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isSupplementOrOtc =
              itemType == 'supplement' || itemType == 'otc';

          return AlertDialog(
            backgroundColor: const Color(0xFF111111),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              existing == null
                  ? 'Add Medication or Supplement'
                  : 'Edit Medication or Supplement',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: itemType,
                    dropdownColor: const Color(0xFF111111),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'prescription',
                        child: Text('Prescription'),
                      ),
                      DropdownMenuItem(
                        value: 'supplement',
                        child: Text('Supplement'),
                      ),
                      DropdownMenuItem(
                        value: 'otc',
                        child: Text('OTC'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => itemType = value);
                    },
                  ),
                  const Divider(height: 1),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const Divider(height: 1),
                  TextField(
                    controller: doseCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText:
                          isSupplementOrOtc ? 'Amount Taken' : 'Dose / Strength',
                      labelStyle: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const Divider(height: 1),
                  TextField(
                    controller: freqCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Frequency',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const Divider(height: 1),
                  if (isSupplementOrOtc) ...[
                    TextField(
                      controller: servingSizeCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Serving Size',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const Divider(height: 1),
                    TextField(
                      controller: activeIngredientsCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Supplement Facts',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      minLines: 2,
                      maxLines: 5,
                    ),
                    const Divider(height: 1),
                    TextField(
                      controller: otherIngredientsCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Other Ingredients',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const Divider(height: 1),
                  ] else ...[
                    TextField(
                      controller: pharmacyCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Pharmacy (and phone)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      maxLines: 2,
                    ),
                    const Divider(height: 1),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) {
      nameCtrl.dispose();
      doseCtrl.dispose();
      freqCtrl.dispose();
      pharmacyCtrl.dispose();
      servingSizeCtrl.dispose();
      activeIngredientsCtrl.dispose();
      otherIngredientsCtrl.dispose();
      return;
    }

    final m = Medication(
      name: nameCtrl.text.trim(),
      dose: doseCtrl.text.trim(),
      frequency: freqCtrl.text.trim(),
      prescriber: pharmacyCtrl.text.trim(),
      source: existing?.source ?? (prefill != null ? 'Scanned' : 'Manual'),
      itemType: itemType,
      servingSize: servingSizeCtrl.text.trim(),
      activeIngredients: _stringList(activeIngredientsCtrl.text),
      otherIngredients: _stringList(otherIngredientsCtrl.text),
      updatedAt: DateTime.now(),
    );

    nameCtrl.dispose();
    doseCtrl.dispose();
    freqCtrl.dispose();
    pharmacyCtrl.dispose();
    servingSizeCtrl.dispose();
    activeIngredientsCtrl.dispose();
    otherIngredientsCtrl.dispose();

    setState(() {
      if (existing == null) {
        _p!.meds.add(m);
      } else {
        _p!.meds[index!] = m;
      }
    });

    await _save();
  }

  // ----------------------------
  // SCAN LABEL
  // ----------------------------

  Future<String?> _showScanIssueDialog({
    required String title,
    required String message,
    bool allowManualEntry = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        actions: [
          Column(
            children: [
              if (allowManualEntry) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, "manual"),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text("Enter Manually"),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, "ok"),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text("OK"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<String?> _chooseScannedItemType() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'What are you adding?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        actions: [
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, 'prescription'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Prescription Medication'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, 'supplement'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Supplement / OTC'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );

    return choice;
  }

  Future<void> _scanLabel() async {
    if (_scanning) return;
    setState(() => _scanning = true);

    try {
      final imagePaths = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (_) => const VitalinkCameraCaptureScreen(
            title: 'Add Medication or Supplement',
            reviewTitle: 'Can you read the label?',
            instructions:
                'Hold the phone steady and fill the screen with the label.',
            addAnotherLabel: 'Add Another Side',
          ),
        ),
      );

      final List<String> base64Images = [];
      for (final path in imagePaths ?? <String>[]) {
        final bytes = await File(path).readAsBytes();
        base64Images.add(base64Encode(bytes));
      }

      if (base64Images.isEmpty) return;

      const url =
          "https://vitalink-app.netlify.app/.netlify/functions/parse_label";

      final store = SecureStore();
      final userId = await store.getString("userId");
      final sessionToken = await store.getString("userSessionToken");

      if (userId == null ||
          userId.isEmpty ||
          sessionToken == null ||
          sessionToken.isEmpty) {
        throw Exception("Please log in again before scanning.");
      }

      final resp = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "images": base64Images,
          "userId": userId,
          "sessionToken": sessionToken,
        }),
      );

      if (resp.statusCode != 200) {
        if (!mounted) return;
        final choice = await _showScanIssueDialog(
          title: "Could Not Read Label",
          message:
              "VitaLink could not read this medication label. Please try again with brighter lighting, hold the phone steady, or enter the medication manually.",
          allowManualEntry: true,
        );
        if (choice == "manual" && mounted) {
          await _addOrEdit();
        }
        return;
      }

      final parsed = jsonDecode(resp.body);
      final data = _normalizeParsed(parsed['data'] ?? parsed);

      final scannedName =
          _stripBrandMarks((data['name'] ?? "").toString().trim());
      final scannedDose =
          _stripBrandMarks((data['dose'] ?? "").toString().trim());
      final scannedFreq = (data['frequency'] ?? "").toString().trim();
      final pharmacyDisplay = _buildPharmacyDisplay(data);
      var itemType = _normalizeItemType(data['item_type'] ?? data['itemType']);
      final servingSize = _stripBrandMarks(
          (data['serving_size'] ?? data['servingSize'] ?? "").toString().trim());
      final activeIngredients = _stripBrandMarksFromList(
          _stringList(data['active_ingredients'] ?? data['activeIngredients']));
      final otherIngredients = _stripBrandMarksFromList(
          _stringList(data['other_ingredients'] ?? data['otherIngredients']));

      if (scannedName.isEmpty) {
        if (!mounted) return;
        final choice = await _showScanIssueDialog(
          title: "No Medication or Supplement Found",
          message:
              "The scan completed, but no medication or supplement name was found. Retake the photo with the label flat, close, and well-lit, or enter it manually.",
          allowManualEntry: true,
        );
        if (choice == "manual" && mounted) {
          await _addOrEdit();
        }
        return;
      }

      if (itemType == 'unknown') {
        if (!mounted) return;
        final selectedType = await _chooseScannedItemType();
        if (selectedType == null) return;
        itemType = selectedType;
      }

      final normalizedScannedName = _normalizeMed(scannedName);

      final existingIndex = _p!.meds.indexWhere((m) =>
          _normalizeMed(m.name) == normalizedScannedName &&
          m.itemType == itemType);

      if (existingIndex != -1) {
        final existing = _p!.meds[existingIndex];

        if (!mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF111111),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              "This ${_typeLabel(existing.itemType)} Is Already Saved",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "You already have:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "${existing.name} ${existing.dose}".trim(),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  "The label says:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "$scannedName $scannedDose".trim(),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text(
                  "What would you like to do?",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            actions: [
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, "replace"),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: Text("Update This ${_typeLabel(existing.itemType)}"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, "add"),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text("Keep Both"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context, "cancel"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                    child: const Text("Cancel"),
                  ),
                ],
              ),
            ],
          ),
        );

        if (choice == "replace") {
          setState(() {
            _p!.meds[existingIndex] = Medication(
              name: scannedName,
              dose: scannedDose,
              frequency: scannedFreq,
              prescriber: pharmacyDisplay,
              source: "Scanned",
              itemType: itemType,
              servingSize: servingSize,
              activeIngredients: activeIngredients,
              otherIngredients: otherIngredients,
              updatedAt: DateTime.now(),
            );
          });
          await _save();
        } else if (choice == "add") {
          setState(() {
            _p!.meds.add(Medication(
              name: scannedName,
              dose: scannedDose,
              frequency: scannedFreq,
              prescriber: pharmacyDisplay,
              source: "Scanned",
              itemType: itemType,
              servingSize: servingSize,
              activeIngredients: activeIngredients,
              otherIngredients: otherIngredients,
              updatedAt: DateTime.now(),
            ));
          });
          await _save();
        }
      } else {
        await _addOrEdit(prefill: {
          "name": scannedName,
          "dose": scannedDose,
          "frequency": scannedFreq,
          "prescriber": pharmacyDisplay,
          "item_type": itemType,
          "serving_size": servingSize,
          "active_ingredients": activeIngredients,
          "other_ingredients": otherIngredients,
        });
      }

      final docName = (data['prescribing_doctor'] ?? "").toString().trim();
      if (itemType == 'prescription' && docName.isNotEmpty) {
        final normalizedParsed = _normalizeName(docName);
        final normalizedProfile = _normalizeName(_p!.fullName);

        if (normalizedParsed != normalizedProfile &&
            !_doctorExistsByNormalizedName(docName)) {
          final formatted = _toLastFirstFormat(docName);
          final specialty = await _chooseDoctorSpecialty(formatted);

          setState(() {
            _p!.doctors.add(Doctor(
              name: formatted,
              specialty: specialty,
              clinic: "",
              phone: "",
            ));
          });

          await _save();
        }
      }
    } catch (e) {
      debugPrint("Scan error: $e");
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove medication?"),
        content: Text(_p!.meds[i].name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Remove")),
        ],
      ),
    );

    if (ok == true) {
      setState(() => _p!.meds.removeAt(i));
      await _save();
    }
  }

  Widget _buildMedicationTile(int index) {
    final m = _p!.meds[index];
    final subtitle = m.isSupplementOrOtc
        ? _supplementPreview(m)
        : "${m.dose} ${m.frequency}".trim();

    return ListTile(
      tileColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: Colors.black12),
      ),
      leading: Icon(
        m.isSupplementOrOtc
            ? Icons.spa_outlined
            : Icons.medication_outlined,
      ),
      title: Text(m.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      onTap: () => _addOrEdit(existing: m, index: index),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(index),
      ),
    );
  }

  Widget _buildSection(String title, List<int> indexes) {
    if (indexes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...indexes.map(_buildMedicationTile),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final meds = _p!.meds;
    final prescriptionIndexes = <int>[];
    final supplementIndexes = <int>[];

    for (var i = 0; i < meds.length; i++) {
      if (meds[i].isSupplementOrOtc) {
        supplementIndexes.add(i);
      } else {
        prescriptionIndexes.add(i);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: ElevatedButton.icon(
                  onPressed: _scanning ? null : _scanLabel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text(
                    'Add Medication or Supplement',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: meds.isEmpty
                    ? const Center(
                        child: Text('No medications yet. Tap + to add.'))
                    : ListView(
                        children: [
                          _buildSection('Prescriptions', prescriptionIndexes),
                          _buildSection('Supplements & OTC', supplementIndexes),
                        ],
                      ),
              ),
            ],
          ),
          if (_scanning)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "Reading your medication label...",
                      style: TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
