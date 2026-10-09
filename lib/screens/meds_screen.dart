// lib/screens/meds_screen.dart
import 'dart:convert';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../services/npi_verification_service.dart';
import '../services/api_service.dart';
import '../widgets/npi_verification_widgets.dart';
import '../widgets/working_overlay.dart';
import 'vitalink_camera_capture_screen.dart';

class MedsScreen extends StatefulWidget {
  const MedsScreen({super.key});

  @override
  State<MedsScreen> createState() => _MedsScreenState();
}

class _MedsScreenState extends State<MedsScreen> {
  late final DataRepository _repo;
  late final NpiVerificationService _npiService;
  Profile? _p;
  bool _loading = true;
  bool _captureInProgress = false;
  bool _scanning = false;
  bool _manualWorking = false;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _npiService = NpiVerificationService();
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
    await ApiService.syncProfilesToServer();
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

      final targetHasInitialOrShortName = targetParts.any(
        (part) => part.length <= 2,
      );
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

  String _supplementPreview(Medication m) {
    final parts = <String>[
      if (m.dose.isNotEmpty) m.dose,
      if (m.frequency.isNotEmpty) m.frequency,
      if (m.servingSize.isNotEmpty)
        '${AppStrings.of(context).servingLabel}: ${m.servingSize}',
      if (m.activeIngredients.isNotEmpty)
        '${AppStrings.of(context).supplementFactsLabel}: ${m.activeIngredients.take(3).join(", ")}',
    ];
    return parts.join(' • ');
  }

  // Supplement labels are full of ™/® marks (and mis-encoded versions of
  // them); keep them out of saved names and ingredients.
  String _stripBrandMarks(String value) {
    return value
        .replaceAll(RegExp(r'(™|®|℠|©)'), '')
        .replaceAll(
          RegExp(r'(â„¢|Â®|â„ |Â©|&trade;|&reg;)', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _stripBrandMarksFromList(List<String> values) {
    return values
        .map(_stripBrandMarks)
        .where((value) => value.isNotEmpty)
        .toList();
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

  String _pharmacyName(String value) {
    final firstLine = value.split(RegExp(r'[\r\n]+')).first.trim();
    return firstLine
        .replaceAll(RegExp(r'\(?\d{3}\)?[\s.-]*\d{3}[\s.-]*\d{4}'), '')
        .trim();
  }

  String _pharmacyPhone(String value) {
    final match = RegExp(
      r'\(?\d{3}\)?[\s.-]*\d{3}[\s.-]*\d{4}',
    ).firstMatch(value);
    return match?.group(0)?.trim() ?? '';
  }

  Future<String?> _askPharmacyType(String name) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).isMailOrderPharmacy(name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(AppStrings.of(context).noLocalPharmacy),
              onTap: () => Navigator.pop(dialogContext, 'retail'),
            ),
            ListTile(
              title: Text(AppStrings.of(context).yesMailOrder),
              onTap: () => Navigator.pop(dialogContext, 'mail_order'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.of(context).notSure),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyPharmacy(int index) async {
    if (index < 0 || index >= _p!.meds.length) return;
    final medication = _p!.meds[index];
    final name = _pharmacyName(medication.prescriber);
    if (name.isEmpty) {
      medication.pharmacyNpi = null;
      medication.pharmacyVerificationStatus = 'unverified';
      medication.pharmacyNpiCandidates = [];
      medication.pharmacyVerifiedAt = null;
      medication.pharmacyVerifiedBy = null;
      await _save();
      return;
    }

    var pharmacyType = medication.pharmacyFulfillmentType;
    if (pharmacyType != 'retail' && pharmacyType != 'mail_order') {
      for (final other in _p!.meds) {
        if (identical(other, medication) ||
            other.prescriber.trim().toLowerCase() !=
                medication.prescriber.trim().toLowerCase()) {
          continue;
        }
        if (other.pharmacyFulfillmentType == 'retail' ||
            other.pharmacyFulfillmentType == 'mail_order') {
          pharmacyType = other.pharmacyFulfillmentType;
          break;
        }
      }
    }
    if (pharmacyType != 'retail' && pharmacyType != 'mail_order') {
      pharmacyType = await _askPharmacyType(name);
      if (!mounted || pharmacyType == null) return;
    }
    medication.pharmacyFulfillmentType = pharmacyType;
    await _save();

    var result = await _npiService.lookup(
      entityType: 'pharmacy',
      name: name,
      city: _p!.city,
      state: _p!.state,
      postalCode: _p!.zip,
      phone: _pharmacyPhone(medication.prescriber),
      mailOrder: pharmacyType == 'mail_order',
    );
    if (result.hasError) {
      await _showVerificationError('pharmacy', result.error);
      return;
    }
    while (mounted) {
      medication.pharmacyNpi = result.npi;
      medication.pharmacyVerificationStatus = result.status;
      medication.pharmacyNpiCandidates = result.candidates;
      medication.pharmacyVerifiedAt = result.isVerified ? DateTime.now() : null;
      medication.pharmacyVerifiedBy =
          result.isVerified ? result.verifiedBy ?? 'auto' : null;
      await _save();
      if (result.isVerified || !mounted) return;

      final selected = await showNpiCandidatePicker(
        context: context,
        title: AppStrings.of(context).whichPharmacyIs(name),
        candidates: result.candidates,
        allowAlternateZip: pharmacyType != 'mail_order',
        candidateLimit: 10,
      );
      if (selected == null || !mounted) return;
      if (selected['_pickerAction'] == 'searchAnotherZip') {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        final zip = await showPharmacyZipPrompt(context: context);
        if (zip == null || !mounted) return;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        result = await _npiService.lookup(
          entityType: 'pharmacy',
          name: name,
          postalCode: zip,
        );
        if (result.hasError) {
          await _showVerificationError('pharmacy', result.error);
          return;
        }
        continue;
      }

      final confirmed = await _npiService.confirm(
        entityType: 'pharmacy',
        searchedName: name,
        candidate: selected,
      );
      if (confirmed == null) return;
      medication.pharmacyNpi = confirmed['npi']?.toString();
      medication.pharmacyVerificationStatus = 'verified';
      medication.pharmacyVerifiedAt = DateTime.now();
      medication.pharmacyVerifiedBy = confirmed['verifiedBy']?.toString();
      await _save();
      return;
    }
  }

  Future<void> _showVerificationError(String item, String? error) async {
    if (!mounted) return;
    final unauthorized = error == 'Unauthorized';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).couldNotCheck(item)),
        content: Text(
          unauthorized
              ? AppStrings.of(context).sessionNotVerifiedRetry
              : AppStrings.of(context).providerSearchUnreachable,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyDoctor(int index) async {
    if (index < 0 || index >= _p!.doctors.length) return;
    final doctor = _p!.doctors[index];
    final registeredZip = _p!.zip?.trim() ?? '';
    final hasRegisteredZip = RegExp(r'^\d{5}$').hasMatch(registeredZip);
    var searchZip = hasRegisteredZip
        ? registeredZip
        : await showDoctorZipPrompt(context: context, doctorName: doctor.name);
    if (searchZip == null || !mounted) return;

    var result = await _npiService.lookup(
      entityType: 'provider',
      name: doctor.name,
      postalCode: searchZip,
      state: _p!.state,
      includeVa: _p!.isVeteran,
    );
    if (result.hasError) {
      await _showVerificationError('doctor', result.error);
      return;
    }
    applyProviderLookupResult(doctor, result);
    await _save();

    if (result.candidates.isEmpty && hasRegisteredZip && mounted) {
      searchZip = await showDoctorZipPrompt(
        context: context,
        doctorName: doctor.name,
        registeredZip: registeredZip,
      );
      if (searchZip == null || !mounted) return;
      result = await _npiService.lookup(
        entityType: 'provider',
        name: doctor.name,
        postalCode: searchZip,
        state: _p!.state,
        includeVa: _p!.isVeteran,
      );
      if (result.hasError) {
        await _showVerificationError('doctor', result.error);
        return;
      }
      applyProviderLookupResult(doctor, result);
      await _save();
    }

    if (result.status != 'needs_review' ||
        result.candidates.isEmpty ||
        !mounted) {
      return;
    }

    final selected = await showNpiCandidatePicker(
      context: context,
      title: AppStrings.of(context).whichProviderIs(doctor.name),
      candidates: result.candidates,
    );
    if (selected == null) return;
    final confirmed = await _npiService.confirm(
      entityType: 'provider',
      searchedName: doctor.name,
      candidate: selected,
    );
    if (confirmed == null) return;
    doctor.npi = confirmed['npi']?.toString();
    doctor.verificationStatus = 'verified';
    doctor.verifiedAt = DateTime.now();
    doctor.verifiedBy = confirmed['verifiedBy']?.toString();
    if (doctor.specialty.trim().isEmpty) {
      doctor.specialty = confirmed['taxonomy']?.toString().trim() ?? '';
    }
    await _save();
  }

  // ----------------------------
  // ADD / EDIT DIALOG
  // ----------------------------

  Future<void> _addOrEdit({
    Medication? existing,
    int? index,
    Map<String, dynamic>? prefill,
  }) async {
    int? targetIndex = index;
    String itemType = _normalizeItemType(
      prefill?['item_type'] ?? prefill?['itemType'] ?? existing?.itemType,
    );
    if (itemType == 'unknown') itemType = 'prescription';
    final servingSizeCtrl = TextEditingController(
      text: (prefill?['serving_size'] ??
              prefill?['servingSize'] ??
              existing?.servingSize ??
              '')
          .toString(),
    );
    final activeIngredientsCtrl = TextEditingController(
      text: _joinLines(_stringList(prefill?['active_ingredients'] ??
          prefill?['activeIngredients'] ??
          existing?.activeIngredients)),
    );
    final otherIngredientsCtrl = TextEditingController(
      text: _joinLines(_stringList(prefill?['other_ingredients'] ??
          prefill?['otherIngredients'] ??
          existing?.otherIngredients)),
    );
    final nameCtrl = TextEditingController(
      text: prefill?['name'] ?? existing?.name ?? '',
    );
    final doseCtrl = TextEditingController(
      text: prefill?['dose'] ?? existing?.dose ?? '',
    );
    final freqCtrl = TextEditingController(
      text: prefill?['frequency'] ?? existing?.frequency ?? '',
    );
    final quantityCtrl = TextEditingController(
      text: prefill?['quantity'] ?? existing?.quantity ?? '',
    );
    final pharmacyCtrl = TextEditingController(
      text: prefill?['prescriber'] ?? existing?.prescriber ?? '',
    );
    String? pharmacyType = existing?.pharmacyFulfillmentType;
    var pharmacyTypeChanged = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isSupplementOrOtc =
              itemType == 'supplement' || itemType == 'otc';
          return AlertDialog(
            backgroundColor: const Color(0xFF111111),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              existing == null
                  ? AppStrings.of(context).addMedicationOrSupplement
                  : AppStrings.of(context).editMedicationOrSupplement,
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
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).typeLabel,
                      labelStyle: const TextStyle(color: Colors.white70),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'prescription',
                        child: Text(AppStrings.of(context).typePrescription),
                      ),
                      DropdownMenuItem(
                        value: 'supplement',
                        child: Text(AppStrings.of(context).typeSupplement),
                      ),
                      DropdownMenuItem(
                          value: 'otc',
                          child: Text(AppStrings.of(context).typeOtc)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => itemType = value);
                    },
                  ),
                  const Divider(height: 1),
                  Column(
                    children: [
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: AppStrings.of(context).name,
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                  Column(
                    children: [
                      TextField(
                        controller: quantityCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: AppStrings.of(context).quantity,
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                  Column(
                    children: [
                      TextField(
                        controller: doseCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: isSupplementOrOtc
                              ? AppStrings.of(context).amountTaken
                              : AppStrings.of(context).doseStrength,
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                  Column(
                    children: [
                      TextField(
                        controller: freqCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: AppStrings.of(context).frequency,
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                  if (isSupplementOrOtc) ...[
                    TextField(
                      controller: servingSizeCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).servingSize,
                        labelStyle: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    const Divider(height: 1),
                    TextField(
                      controller: activeIngredientsCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).supplementFactsLabel,
                        labelStyle: const TextStyle(color: Colors.white70),
                      ),
                      minLines: 2,
                      maxLines: 5,
                    ),
                    const Divider(height: 1),
                    TextField(
                      controller: otherIngredientsCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).otherIngredientsLabel,
                        labelStyle: const TextStyle(color: Colors.white70),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const Divider(height: 1),
                  ] else ...[
                    Column(
                      children: [
                        TextField(
                          controller: pharmacyCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: AppStrings.of(context).pharmacyAndPhone,
                            labelStyle: const TextStyle(color: Colors.white70),
                          ),
                          maxLines: 2,
                        ),
                        const Divider(height: 1),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: pharmacyType,
                      dropdownColor: const Color(0xFF111111),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).pharmacyType,
                        labelStyle: const TextStyle(color: Colors.white70),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'retail',
                          child: Text(AppStrings.of(context).localPharmacy),
                        ),
                        DropdownMenuItem(
                          value: 'mail_order',
                          child: Text(AppStrings.of(context).mailOrder),
                        ),
                      ],
                      onChanged: (value) {
                        pharmacyType = value;
                        pharmacyTypeChanged = true;
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: Text(AppStrings.of(context).cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                child: Text(AppStrings.of(context).save),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    final ownsWorkingOverlay = !_scanning;
    if (ownsWorkingOverlay && mounted) {
      setState(() => _manualWorking = true);
    }

    try {
      if (existing != null &&
          _pharmacyName(existing.prescriber).toLowerCase() !=
              _pharmacyName(pharmacyCtrl.text).toLowerCase() &&
          !pharmacyTypeChanged) {
        pharmacyType = null;
      }

      final m = Medication(
        name: nameCtrl.text.trim(),
        dose: doseCtrl.text.trim(),
        frequency: freqCtrl.text.trim(),
        quantity: quantityCtrl.text.trim(),
        prescriber: pharmacyCtrl.text.trim(),
        pharmacyFulfillmentType: pharmacyType,
        source: existing?.source ?? (prefill != null ? 'Scanned' : 'Manual'),
        itemType: itemType,
        servingSize: servingSizeCtrl.text.trim(),
        activeIngredients: _stringList(activeIngredientsCtrl.text),
        otherIngredients: _stringList(otherIngredientsCtrl.text),
        updatedAt: DateTime.now(),
      );

      setState(() {
        if (existing == null) {
          _p!.meds.add(m);
          targetIndex = _p!.meds.length - 1;
        } else {
          _p!.meds[index!] = m;
        }
      });

      await _save();
      // Supplements and OTC items have no pharmacy to verify.
      if (!m.isSupplementOrOtc) await _verifyPharmacy(targetIndex!);
    } finally {
      if (ownsWorkingOverlay && mounted) {
        setState(() => _manualWorking = false);
      }
    }
  }

  // ----------------------------
  // SCAN LABEL
  // ----------------------------

  Future<List<Map<String, String>>?> _resolveScannedMedicationDuplicates(
    List<Map<String, String>> medications,
  ) async {
    final groups = <String, List<int>>{};
    for (var index = 0; index < medications.length; index++) {
      final key = _normalizeMed(medications[index]['name'] ?? '');
      groups.putIfAbsent(key, () => <int>[]).add(index);
    }

    final included = List<bool>.filled(medications.length, true);
    for (final indexes in groups.values.where((group) => group.length > 1)) {
      final doses = indexes
          .map((index) => medications[index]['dose']!.trim().toLowerCase())
          .toSet();

      if (doses.length == 1) {
        if (!mounted) return null;
        final medication = medications[indexes.first];
        final keepBoth = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(AppStrings.of(context)
                .appearsMoreThanOnce('${medication['name']}')),
            content: Text(
              AppStrings.of(context).listShowsTimes(
                '${medication['name']}',
                '${medication['dose']}',
                indexes.length,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppStrings.of(context).saveOnce),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  indexes.length == 2
                      ? AppStrings.of(context).iTakeBoth
                      : AppStrings.of(context).iTakeAll,
                ),
              ),
            ],
          ),
        );
        if (keepBoth == null) return null;
        if (!keepBoth) {
          for (final index in indexes.skip(1)) {
            included[index] = false;
          }
        }
        continue;
      }

      if (!mounted) return null;
      final selected = <int>{...indexes};
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              '${medications[indexes.first]['name']} has multiple strengths',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.of(context).selectEveryStrength()),
                const SizedBox(height: 12),
                ...indexes.map(
                  (index) {
                    final details = <String>[
                      if (medications[index]['frequency']!.isNotEmpty)
                        medications[index]['frequency']!,
                      if (medications[index]['quantity']!.isNotEmpty)
                        AppStrings.of(context)
                            .quantityValue('${medications[index]['quantity']}'),
                    ];
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(index),
                      title: Text(
                        AppStrings.of(context).rowStrength(
                          index + 1,
                          medications[index]['dose']!.isEmpty
                              ? AppStrings.of(context).strengthNotShown
                              : medications[index]['dose']!,
                        ),
                      ),
                      subtitle:
                          details.isEmpty ? null : Text(details.join(' - ')),
                      onChanged: (value) => setDialogState(() {
                        if (value ?? false) {
                          selected.add(index);
                        } else {
                          selected.remove(index);
                        }
                      }),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppStrings.of(context).cancelScan),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(AppStrings.of(context).useSelected),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return null;
      for (final index in indexes) {
        included[index] = selected.contains(index);
      }
    }

    return [
      for (var index = 0; index < medications.length; index++)
        if (included[index]) medications[index],
    ];
  }

  Future<List<Map<String, String>>?> _reviewScannedMedicationList(
    List<Map<String, String>> medications,
  ) async {
    final controllers = medications
        .map(
          (medication) => {
            'name': TextEditingController(text: medication['name']),
            'dose': TextEditingController(text: medication['dose']),
            'frequency': TextEditingController(text: medication['frequency']),
            'quantity': TextEditingController(text: medication['quantity']),
          },
        )
        .toList();
    final included = List<bool>.filled(controllers.length, true);

    final reviewed = await showDialog<List<Map<String, String>>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context)
              .reviewMedicationsTitle(controllers.length)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppStrings.of(context).confirmEveryMedication()),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: controllers.length,
                    separatorBuilder: (_, __) => const Divider(height: 24),
                    itemBuilder: (_, index) {
                      final row = controllers[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: included[index],
                            onChanged: (value) => setDialogState(
                              () => included[index] = value ?? false,
                            ),
                            title: Text(AppStrings.of(context)
                                .medicationNumber(index + 1)),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          TextField(
                            controller: row['name'],
                            enabled: included[index],
                            decoration: InputDecoration(
                                labelText: AppStrings.of(context).name),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: row['dose'],
                                  enabled: included[index],
                                  decoration: InputDecoration(
                                    labelText: AppStrings.of(context).strength,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: row['quantity'],
                                  enabled: included[index],
                                  decoration: InputDecoration(
                                    labelText: AppStrings.of(context).quantity,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          TextField(
                            controller: row['frequency'],
                            enabled: included[index],
                            decoration: InputDecoration(
                              labelText:
                                  AppStrings.of(context).directionsFrequency,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).cancel),
            ),
            FilledButton(
              onPressed: () {
                final result = <Map<String, String>>[];
                for (var index = 0; index < controllers.length; index++) {
                  if (!included[index]) continue;
                  final row = controllers[index];
                  final name = row['name']!.text.trim();
                  if (name.isEmpty) continue;
                  result.add({
                    'name': name,
                    'dose': row['dose']!.text.trim(),
                    'frequency': row['frequency']!.text.trim(),
                    'quantity': row['quantity']!.text.trim(),
                  });
                }
                Navigator.pop(dialogContext, result);
              },
              child: Text(AppStrings.of(context).saveSelected),
            ),
          ],
        ),
      ),
    );

    return reviewed;
  }

  List<Map<String, String>> _parsedMedicationList(
    Map<String, dynamic> data,
  ) {
    final raw = data['medications'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => {
                'name': (item['name'] ?? '').toString().trim(),
                'dose': (item['dose'] ?? '').toString().trim(),
                'frequency': (item['frequency'] ?? '').toString().trim(),
                'quantity': (item['quantity'] ?? '').toString().trim(),
              })
          .where((item) => item['name']!.isNotEmpty)
          .toList();
    }
    return [];
  }

  Future<String?> _showScanIssueDialog({
    required String title,
    required String message,
    bool allowManualEntry = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
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
                    child: Text(AppStrings.of(context).enterManually),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, "ok"),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text("OK"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _scanLabel() async {
    if (_scanning || _captureInProgress) return;
    setState(() => _captureInProgress = true);

    try {
      final imagePaths = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (_) => VitalinkCameraCaptureScreen(
            title: AppStrings.of(context).scanLabelOrList,
            reviewTitle: AppStrings.of(context).canYouReadEveryItem,
            instructions: AppStrings.of(context).scanLabelInstructions,
            addAnotherLabel: AppStrings.of(context).addAnotherPage,
          ),
        ),
      );

      final List<String> base64Images = [];
      for (final path in imagePaths ?? <String>[]) {
        final bytes = await File(path).readAsBytes();
        base64Images.add(base64Encode(bytes));
      }

      if (base64Images.isEmpty) return;

      if (mounted) {
        setState(() {
          _captureInProgress = false;
          _scanning = true;
        });
      }

      const url =
          "https://vitalink-app.netlify.app/.netlify/functions/parse_label";

      final store = SecureStore();
      final userId = await store.getString("userId");
      final sessionToken = await store.getString("userSessionToken");

      if (userId == null ||
          userId.isEmpty ||
          sessionToken == null ||
          sessionToken.isEmpty) {
        if (!mounted) return;
        throw Exception(AppStrings.of(context).logInAgainBeforeScanning);
      }

      final resp = await http
          .post(
            Uri.parse(url),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "images": base64Images,
              "userId": userId,
              "sessionToken": sessionToken,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (resp.statusCode != 200) {
        if (!mounted) return;
        var listTooLong = false;
        try {
          listTooLong = jsonDecode(resp.body)['code'] == 'LIST_TOO_LONG';
        } catch (_) {}
        final choice = await _showScanIssueDialog(
          title: listTooLong
              ? AppStrings.of(context).listTooLong
              : AppStrings.of(context).couldNotReadLabel,
          message: listTooLong
              ? AppStrings.of(context).listTooLongBody
              : AppStrings.of(context).couldNotReadLabelBody,
          allowManualEntry: true,
        );
        if (choice == "manual" && mounted) {
          await _addOrEdit();
        }
        return;
      }

      final parsed = jsonDecode(resp.body);
      final data = _normalizeParsed(parsed['data'] ?? parsed);
      final medicationList = _parsedMedicationList(data);

      final scannedName =
          _stripBrandMarks((data['name'] ?? "").toString().trim());
      final scannedDose =
          _stripBrandMarks((data['dose'] ?? "").toString().trim());
      final scannedFreq = (data['frequency'] ?? "").toString().trim();
      final pharmacyDisplay = _buildPharmacyDisplay(data);
      var itemType = _normalizeItemType(data['item_type'] ?? data['itemType']);
      final servingSize = _stripBrandMarks(
        (data['serving_size'] ?? data['servingSize'] ?? "").toString().trim(),
      );
      final activeIngredients = _stripBrandMarksFromList(
        _stringList(data['active_ingredients'] ?? data['activeIngredients']),
      );
      final otherIngredients = _stripBrandMarksFromList(
        _stringList(data['other_ingredients'] ?? data['otherIngredients']),
      );

      if (medicationList.isEmpty && scannedName.isEmpty) {
        if (!mounted) return;
        final choice = await _showScanIssueDialog(
          title: AppStrings.of(context).noMedicationFound,
          message: AppStrings.of(context).noMedicationFoundBody,
          allowManualEntry: true,
        );
        if (choice == "manual" && mounted) {
          await _addOrEdit();
        }
        return;
      }

      if (medicationList.length > 1) {
        final resolved =
            await _resolveScannedMedicationDuplicates(medicationList);
        if (!mounted || resolved == null) return;
        final reviewed = await _reviewScannedMedicationList(resolved);
        if (!mounted || reviewed == null) return;

        var addedCount = 0;
        var updatedCount = 0;
        final availableExistingIndexes = <int>{
          for (var index = 0; index < _p!.meds.length; index++) index,
        };
        for (final item in reviewed) {
          final name = item['name']!;
          final dose = item['dose']!;
          final frequency = item['frequency']!;
          final quantity = item['quantity']!;
          int? existingIndex;
          for (final index in availableExistingIndexes) {
            final medication = _p!.meds[index];
            if (_normalizeMed(medication.name) == _normalizeMed(name) &&
                medication.dose.trim().toLowerCase() ==
                    dose.trim().toLowerCase()) {
              existingIndex = index;
              break;
            }
          }

          if (existingIndex != null) {
            availableExistingIndexes.remove(existingIndex);
            final existing = _p!.meds[existingIndex];
            existing.name = name;
            existing.dose = dose;
            existing.frequency = frequency;
            existing.quantity = quantity;
            if (pharmacyDisplay.isNotEmpty) {
              existing.prescriber = pharmacyDisplay;
            }
            existing.source = 'Scanned medication list';
            existing.updatedAt = DateTime.now();
            updatedCount++;
          } else {
            _p!.meds.add(
              Medication(
                name: name,
                dose: dose,
                frequency: frequency,
                quantity: quantity,
                prescriber: pharmacyDisplay,
                source: 'Scanned medication list',
                updatedAt: DateTime.now(),
              ),
            );
            addedCount++;
          }
        }
        await _save();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context)
                  .medicationListSaved(addedCount, updatedCount),
            ),
          ),
        );
      } else {
        // The label reader decides the type; never ask the user. An older
        // server may still say "unknown", so decide from the label instead.
        if (itemType == 'unknown') {
          itemType = pharmacyDisplay.isNotEmpty
              ? 'prescription'
              : (servingSize.isNotEmpty || activeIngredients.isNotEmpty)
                  ? 'supplement'
                  : 'prescription';
        }

        final normalizedScannedName = _normalizeMed(scannedName);

        final existingIndex = _p!.meds.indexWhere(
          (m) =>
              _normalizeMed(m.name) == normalizedScannedName &&
              m.itemType == itemType,
        );

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
                AppStrings.of(context).alreadySavedTitle(existing.itemType),
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
                  Text(
                    AppStrings.of(context).youAlreadyHave,
                    style: const TextStyle(
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
                  Text(
                    AppStrings.of(context).theLabelSays,
                    style: const TextStyle(
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
                  Text(
                    AppStrings.of(context).whatWouldYouLikeToDo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
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
                        child: Text(
                          AppStrings.of(context)
                              .updateThisItem(existing.itemType),
                        ),
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
                        child: Text(AppStrings.of(context).keepBoth),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context, "cancel"),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      child: Text(AppStrings.of(context).cancel),
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
            if (itemType == 'prescription') {
              await _verifyPharmacy(existingIndex);
            }
          } else if (choice == "add") {
            late final int addedIndex;
            setState(() {
              _p!.meds.add(
                Medication(
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
                ),
              );
              addedIndex = _p!.meds.length - 1;
            });
            await _save();
            if (itemType == 'prescription') {
              await _verifyPharmacy(addedIndex);
            }
          }
        } else {
          await _addOrEdit(
            prefill: {
              "name": scannedName,
              "dose": scannedDose,
              "frequency": scannedFreq,
              "quantity": (data['quantity'] ?? '').toString().trim(),
              "prescriber": pharmacyDisplay,
              "item_type": itemType,
              "serving_size": servingSize,
              "active_ingredients": activeIngredients,
              "other_ingredients": otherIngredients,
            },
          );
        }
      }

      final docName = (data['prescribing_doctor'] ?? "").toString().trim();
      // Supplement labels have no prescriber; only add doctors from
      // prescriptions and pill-pack lists.
      if (itemType != 'supplement' && itemType != 'otc' && docName.isNotEmpty) {
        final normalizedParsed = _normalizeName(docName);
        final normalizedProfile = _normalizeName(_p!.fullName);

        if (normalizedParsed != normalizedProfile &&
            !_doctorExistsByNormalizedName(docName)) {
          final formatted = _toLastFirstFormat(docName);

          setState(() {
            _p!.doctors.add(
              Doctor(name: formatted, specialty: '', clinic: "", phone: ""),
            );
          });

          await _save();
          await _verifyDoctor(_p!.doctors.length - 1);
        }
      }
    } catch (e) {
      debugPrint("Scan error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _captureInProgress = false;
          _scanning = false;
        });
      }
    }
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).removeMedication),
        content: Text(_p!.meds[i].name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).remove),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() => _p!.meds.removeAt(i));
      await _save();
    }
  }

  Widget _buildMedicationTile(int i) {
    final m = _p!.meds[i];
    if (m.isSupplementOrOtc) {
      final preview = _supplementPreview(m);
      return ListTile(
        tileColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: Colors.black12)),
        leading: const Icon(Icons.spa_outlined),
        title: Text(m.name),
        subtitle: preview.isEmpty ? null : Text(preview),
        onTap: () => _addOrEdit(existing: m, index: i),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _delete(i),
        ),
      );
    }
    return ListTile(
      leading: const Icon(Icons.medication_outlined),
      tileColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: Colors.black12),
      ),
      title: Text(m.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              m.dose,
              m.frequency,
              if (m.quantity.isNotEmpty) 'Qty ${m.quantity}',
            ].where((value) => value.isNotEmpty).join(' - '),
          ),
          if (_pharmacyName(m.prescriber).isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '${_pharmacyName(m.prescriber)}${m.pharmacyFulfillmentType == 'mail_order' ? ' (${AppStrings.of(context).mailOrder})' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                npiStatusIcon(
                  m.pharmacyVerificationStatus,
                ),
              ],
            ),
        ],
      ),
      onTap: () => _addOrEdit(existing: m, index: i),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(i),
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
      (meds[i].isSupplementOrOtc ? supplementIndexes : prescriptionIndexes)
          .add(i);
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).medications)),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: ElevatedButton.icon(
                  onPressed: _scanning || _captureInProgress || _manualWorking
                      ? null
                      : _scanLabel,
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
                  label: Text(
                    AppStrings.of(context).scanLabelOrList,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Expanded(
                child: meds.isEmpty
                    ? Center(
                        child: Text(AppStrings.of(context).noMedicationsYet),
                      )
                    : ListView(
                        children: [
                          _buildSection(
                              AppStrings.of(context).prescriptionsSection,
                              prescriptionIndexes),
                          _buildSection(
                            AppStrings.of(context).supplementsOtcSection,
                            supplementIndexes,
                          ),
                        ],
                      ),
              ),
            ],
          ),
          if (_scanning)
            WorkingOverlay(
              message: AppStrings.of(context).readingMedicationInfo,
            ),
          if (_manualWorking)
            WorkingOverlay(
              message: AppStrings.of(context).savingCheckingMedication,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scanning || _captureInProgress || _manualWorking
            ? null
            : () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
