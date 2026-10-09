import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../services/npi_verification_service.dart';
import '../services/api_service.dart';
import '../utils/phone_formatter.dart'; // ← NEW
import '../widgets/npi_verification_widgets.dart';
import '../widgets/working_overlay.dart';

class DoctorsScreen extends StatefulWidget {
  const DoctorsScreen({super.key});

  @override
  State<DoctorsScreen> createState() => _DoctorsScreenState();
}

class _DoctorsScreenState extends State<DoctorsScreen> {
  late final DataRepository _repo;
  late final NpiVerificationService _npiService;
  Profile? _p;
  bool _loading = true;
  String? _workingMessage;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _npiService = NpiVerificationService();
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.loadProfile();
    setState(() {
      _p = p;
      _loading = false;
    });
  }

  Future<void> _save() async {
    _p!.updatedAt = DateTime.now();
    await _repo.saveProfile(_p!);
    await ApiService.syncProfilesToServer();
    setState(() {});
  }

  Future<void> _addOrEdit({Doctor? existing, int? index}) async {
    int? targetIndex = index;
    final verifiedCandidate =
        existing == null ? null : verifiedProviderCandidate(existing);
    final isVerifiedRecord =
        existing?.verificationStatus == 'verified' && existing?.npi != null ||
            existing?.verificationStatus == 'va_verified';
    final verifiedName = verifiedCandidate?['displayName']?.toString().trim();
    final name = TextEditingController(
      text: verifiedName?.isNotEmpty == true
          ? verifiedName
          : existing?.name ?? '',
    );
    final specialty = TextEditingController(
      text: existing?.specialty.trim().isNotEmpty == true
          ? existing!.specialty
          : verifiedCandidate?['taxonomy']?.toString() ?? '',
    );
    final verifiedClinic = verifiedCandidate?['vaFacility']?.toString().trim();
    final clinic = TextEditingController(
      text: existing?.clinic.trim().isNotEmpty == true
          ? existing!.clinic
          : verifiedClinic?.isNotEmpty == true
              ? verifiedClinic
              : existing?.vaFacility ?? '',
    );
    final phone = TextEditingController(text: existing?.phone ?? '');
    var isPrimaryCareProvider = existing?.isPrimaryCareProvider ?? false;
    final recordName =
        verifiedCandidate?['displayName']?.toString().trim().isNotEmpty == true
            ? verifiedCandidate!['displayName'].toString().trim()
            : existing?.name.trim() ?? '';
    final recordSpecialty =
        verifiedCandidate?['taxonomy']?.toString().trim().isNotEmpty == true
            ? verifiedCandidate!['taxonomy'].toString().trim()
            : existing?.specialty.trim() ?? '';
    final recordCredential =
        verifiedCandidate?['credential']?.toString().trim() ?? '';
    final recordClinic =
        verifiedCandidate?['vaFacility']?.toString().trim().isNotEmpty == true
            ? verifiedCandidate!['vaFacility'].toString().trim()
            : existing?.vaFacility?.trim().isNotEmpty == true
                ? existing!.vaFacility!.trim()
                : existing?.clinic.trim() ?? '';
    final recordAddress = verifiedCandidate == null
        ? ''
        : [
            verifiedCandidate['address1'],
            verifiedCandidate['city'],
            verifiedCandidate['state'],
            formatRegistryPostalCode(verifiedCandidate['postalCode']),
          ]
            .where((value) => value?.toString().trim().isNotEmpty == true)
            .join(' ');
    final recordPhone =
        verifiedCandidate?['phone']?.toString().trim().isNotEmpty == true
            ? verifiedCandidate!['phone'].toString().trim()
            : existing?.phone.trim() ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null
              ? AppStrings.of(context).addDoctor
              : AppStrings.of(context).editDoctor),
          content: SingleChildScrollView(
            child: Column(
              children: [
                if (!isVerifiedRecord) ...[
                  TextField(
                    controller: name,
                    decoration:
                        InputDecoration(labelText: AppStrings.of(context).name),
                  ),
                  const Divider(height: 1),
                  TextField(
                    controller: specialty,
                    decoration: InputDecoration(
                        labelText: AppStrings.of(context).specialty),
                  ),
                  const Divider(height: 1),
                  TextField(
                    controller: clinic,
                    decoration: InputDecoration(
                        labelText: AppStrings.of(context).clinic),
                  ),
                  const Divider(height: 1),
                  TextField(
                    controller: phone,
                    decoration: InputDecoration(
                        labelText: AppStrings.of(context).phone),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneNumberFormatter()],
                  ),
                  const Divider(height: 1),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppStrings.of(context).primaryCareProvider),
                  value: isPrimaryCareProvider,
                  onChanged: (value) =>
                      setDialogState(() => isPrimaryCareProvider = value),
                ),
                if (existing != null) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      existing.verificationStatus == 'verified' &&
                              existing.npi != null
                          ? AppStrings.of(context)
                              .npiVerifiedValue('${existing.npi}')
                          : existing.verificationStatus == 'va_verified'
                              ? AppStrings.of(context).vaProviderVerifiedAt(
                                  existing.vaFacility ??
                                      AppStrings.of(context).vaDirectory)
                              : existing.verificationStatus == 'needs_review'
                                  ? AppStrings.of(context).npiNeedsReviewSave
                                  : AppStrings.of(context).npiNotVerifiedSave,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (isVerifiedRecord) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppStrings.of(context).registryRecord,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        recordName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (recordSpecialty.isNotEmpty ||
                        recordCredential.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          [recordSpecialty, recordCredential]
                              .where((value) => value.isNotEmpty)
                              .join(' • '),
                        ),
                      ),
                    if (recordClinic.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(recordClinic),
                      ),
                    if (recordAddress.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(recordAddress),
                      ),
                    if (recordPhone.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(recordPhone),
                      ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppStrings.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppStrings.of(context).save),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    // Let the edit dialog finish its reverse transition before another dialog
    // (ZIP prompt or provider picker) can be opened by verification.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    final doc = Doctor(
      name: name.text.trim(),
      specialty: specialty.text.trim(),
      clinic: clinic.text.trim(),
      phone: phone.text.trim(), // ← formatted before save
      isPrimaryCareProvider: isPrimaryCareProvider,
      npi: existing?.npi,
      verificationStatus: existing?.verificationStatus ?? 'unverified',
      npiCandidates: existing?.npiCandidates,
      verifiedAt: existing?.verifiedAt,
      verifiedBy: existing?.verifiedBy,
      isVaProvider: existing?.isVaProvider ?? false,
      vaFacility: existing?.vaFacility,
      vaServiceLine: existing?.vaServiceLine,
      vaVerifiedAt: existing?.vaVerifiedAt,
    );

    setState(() {
      _workingMessage = AppStrings.of(context).savingCheckingDoctor;
      if (existing == null) {
        _p!.doctors.add(doc);
        targetIndex = _p!.doctors.length - 1;
      } else {
        _p!.doctors[index!] = doc;
      }
    });

    try {
      await _save();
      if (!isVerifiedRecord) {
        await _verifyDoctor(targetIndex!);
      }
    } catch (_) {
      if (mounted) {
        if (!mounted) return;
        await _showDoctorLookupMessage(
          AppStrings.of(context).couldNotCheckDoctorBody,
          title: AppStrings.of(context).couldNotCheckDoctor,
        );
      }
    } finally {
      if (mounted) setState(() => _workingMessage = null);
    }
  }

  Future<void> _showDoctorLookupMessage(
    String message, {
    String? title,
  }) async {
    if (!mounted) return;
    final dialogTitle = title ?? AppStrings.of(context).doctorNotVerified;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle),
        content: Text(message),
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
    if (!hasRegisteredZip) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }

    var result = await _npiService.lookup(
      entityType: 'provider',
      name: doctor.name,
      postalCode: searchZip,
      state: _p!.state,
      includeVa: _p!.isVeteran,
    );

    if (result.hasError) {
      if (!mounted) return;
      await _showDoctorLookupMessage(
        result.error == 'Unauthorized'
            ? AppStrings.of(context).sessionNotVerifiedRetryDoctor
            : AppStrings.of(context).providerSearchUnreachable,
        title: AppStrings.of(context).couldNotCheckDoctor,
      );
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
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      result = await _npiService.lookup(
        entityType: 'provider',
        name: doctor.name,
        postalCode: searchZip,
        state: _p!.state,
        includeVa: _p!.isVeteran,
      );
      if (result.hasError) {
        if (!mounted) return;
        await _showDoctorLookupMessage(
          result.error == 'Unauthorized'
              ? AppStrings.of(context).sessionNotVerifiedRetryDoctor
              : AppStrings.of(context).providerSearchUnreachable,
          title: AppStrings.of(context).couldNotCheckDoctor,
        );
        return;
      }
      applyProviderLookupResult(doctor, result);
      await _save();
    }

    Map<String, dynamic>? selected;
    while (mounted) {
      if (result.status != 'needs_review' || result.candidates.isEmpty) {
        if (result.candidates.isEmpty) {
          if (!mounted) return;
          await _showDoctorLookupMessage(
            AppStrings.of(context).couldNotFindDoctorNearZip(doctor.name),
          );
        }
        return;
      }

      if (!mounted) return;
      selected = await showNpiCandidatePicker(
        context: context,
        title: AppStrings.of(context).whichProviderIs(doctor.name),
        candidates: result.candidates,
        allowAlternateZip: true,
      );
      if (selected == null) return;
      if (selected['_pickerAction'] != 'searchAnotherZip') break;

      if (!mounted) return;
      final alternateZip = await showDoctorZipPrompt(
        context: context,
        doctorName: doctor.name,
        refiningSearch: true,
      );
      if (alternateZip == null || !mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      searchZip = alternateZip;
      result = await _npiService.lookup(
        entityType: 'provider',
        name: doctor.name,
        postalCode: searchZip,
        state: _p!.state,
        includeVa: _p!.isVeteran,
      );
      if (result.hasError) {
        if (!mounted) return;
        await _showDoctorLookupMessage(
          result.error == 'Unauthorized'
              ? AppStrings.of(context).sessionNotVerifiedRetryDoctor
              : AppStrings.of(context).providerSearchUnreachable,
          title: AppStrings.of(context).couldNotCheckDoctor,
        );
        return;
      }
      applyProviderLookupResult(doctor, result);
      await _save();
    }

    if (selected == null) return;

    if (selected['npi'] == null && selected['isVaProvider'] == true) {
      doctor.npi = null;
      doctor.verificationStatus = 'va_verified';
      doctor.npiCandidates = result.candidates;
      doctor.verifiedAt = null;
      doctor.verifiedBy = 'va_directory';
      doctor.isVaProvider = true;
      doctor.vaFacility = selected['vaFacility']?.toString();
      doctor.vaServiceLine = selected['vaServiceLine']?.toString();
      doctor.vaVerifiedAt = DateTime.now();
      if (doctor.specialty.trim().isEmpty) {
        doctor.specialty = selected['taxonomy']?.toString().trim() ?? '';
      }
      if (doctor.clinic.trim().isEmpty) {
        doctor.clinic = doctor.vaFacility ?? '';
      }
      await _save();
      return;
    }

    final confirmed = await _npiService.confirm(
      entityType: 'provider',
      searchedName: doctor.name,
      candidate: selected,
    );
    if (confirmed == null) return;

    doctor.npi = confirmed['npi']?.toString();
    doctor.verificationStatus = 'verified';
    doctor.npiCandidates = result.candidates;
    doctor.verifiedAt = DateTime.now();
    doctor.verifiedBy = confirmed['verifiedBy']?.toString();
    doctor.isVaProvider = selected['isVaProvider'] == true;
    doctor.vaFacility = selected['vaFacility']?.toString();
    doctor.vaServiceLine = selected['vaServiceLine']?.toString();
    doctor.vaVerifiedAt = doctor.isVaProvider ? DateTime.now() : null;
    final confirmedName = confirmed['displayName']?.toString().trim() ?? '';
    if (confirmedName.isNotEmpty) {
      doctor.name = confirmedName;
    }
    if (doctor.specialty.trim().isEmpty) {
      doctor.specialty = confirmed['taxonomy']?.toString().trim() ?? '';
    }
    if (doctor.phone.trim().isEmpty) {
      doctor.phone = confirmed['phone']?.toString().trim() ?? '';
    }
    if (doctor.clinic.trim().isEmpty) {
      final confirmedFacility =
          confirmed['vaFacility']?.toString().trim() ?? '';
      final selectedFacility = selected['vaFacility']?.toString().trim() ?? '';
      doctor.clinic =
          confirmedFacility.isNotEmpty ? confirmedFacility : selectedFacility;
    }
    await _save();
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).removeDoctor),
        content: Text(_p!.doctors[i].name),
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
      setState(() => _p!.doctors.removeAt(i));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final docs = _p!.doctors;

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).doctors)),
      body: Stack(
        children: [
          docs.isEmpty
              ? Center(child: Text(AppStrings.of(context).noDoctorsAdded))
              : ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    return ListTile(
                      tileColor: Colors.transparent,
                      shape: const Border(
                        bottom: BorderSide(color: Colors.black12),
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(d.name)),
                          const SizedBox(width: 6),
                          npiStatusIcon(d.verificationStatus),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ([
                            d.specialty,
                            d.clinic,
                            d.phone,
                          ].any((value) => value.isNotEmpty))
                            Text(
                              [
                                if (d.specialty.isNotEmpty)
                                  AppStrings.of(context)
                                      .doctorSpecialtyLabel(d.specialty),
                                if (d.clinic.isNotEmpty) d.clinic,
                                if (d.phone.isNotEmpty) d.phone,
                              ].join(" • "),
                            ),
                          if (d.isPrimaryCareProvider) ...[
                            const SizedBox(height: 3),
                            primaryCareIndicator(),
                          ],
                          if (d.isVaProvider) ...[
                            const SizedBox(height: 3),
                            Text(
                              d.vaFacility?.trim().isNotEmpty == true
                                  ? AppStrings.of(context)
                                      .vaProviderAt('${d.vaFacility}')
                                  : AppStrings.of(context).vaProvider,
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(i),
                      ),
                      onTap: () => _addOrEdit(existing: d, index: i),
                    );
                  },
                ),
          if (_workingMessage != null)
            WorkingOverlay(message: _workingMessage!),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _workingMessage == null ? () => _addOrEdit() : null,
        child: const Icon(Icons.add),
      ),
    );
  }
}
