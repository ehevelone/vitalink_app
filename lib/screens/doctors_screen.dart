import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../services/npi_verification_service.dart';
import '../utils/phone_formatter.dart'; // ← NEW
import '../widgets/npi_verification_widgets.dart';

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
    setState(() {});
  }

  Future<void> _addOrEdit({Doctor? existing, int? index}) async {
    int? targetIndex = index;
    final name = TextEditingController(text: existing?.name ?? '');
    final specialty = TextEditingController(text: existing?.specialty ?? '');
    final clinic = TextEditingController(text: existing?.clinic ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    var isPrimaryCareProvider = existing?.isPrimaryCareProvider ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Doctor' : 'Edit Doctor'),
          content: SingleChildScrollView(
            child: Column(
              children: [
              Column(
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const Divider(height: 1),
                ],
              ),
              Column(
                children: [
                  TextField(
                    controller: specialty,
                    decoration: const InputDecoration(labelText: 'Specialty'),
                  ),
                  const Divider(height: 1),
                ],
              ),
              Column(
                children: [
                  TextField(
                    controller: clinic,
                    decoration: const InputDecoration(labelText: 'Clinic'),
                  ),
                  const Divider(height: 1),
                ],
              ),
              Column(
                children: [
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      PhoneNumberFormatter()
                    ], // ← PHONE FORMATTING ADDED
                  ),
                  const Divider(height: 1),
                ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Primary care provider'),
                  value: isPrimaryCareProvider,
                  onChanged: (value) => setDialogState(
                    () => isPrimaryCareProvider = value,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true) return;

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
    );

    setState(() {
      if (existing == null) {
        _p!.doctors.add(doc);
        targetIndex = _p!.doctors.length - 1;
      } else {
        _p!.doctors[index!] = doc;
      }
    });

    await _save();
    await _verifyDoctor(targetIndex!);
  }

  Future<void> _verifyDoctor(int index) async {
    if (index < 0 || index >= _p!.doctors.length) return;
    final doctor = _p!.doctors[index];
    var result = await _npiService.lookup(
      entityType: 'provider',
      name: doctor.name,
      city: _p!.city,
      state: _p!.state,
    );

    doctor.npi = result.npi;
    doctor.verificationStatus = result.status;
    doctor.npiCandidates = result.candidates;
    doctor.verifiedAt = result.isVerified ? DateTime.now() : null;
    doctor.verifiedBy = result.isVerified ? result.verifiedBy ?? 'auto' : null;
    await _save();

    if (result.status != 'needs_review' ||
        result.candidates.isEmpty ||
        !mounted) {
      return;
    }

    final specialty = await showNpiSpecialtyPicker(
      context: context,
      doctorName: doctor.name,
      initialValue: doctor.specialty,
    );
    if (specialty == null) return;

    doctor.specialty = specialty.displayValue;
    if (specialty.filterLabel != 'Other') {
      result = await _npiService.lookup(
        entityType: 'provider',
        name: doctor.name,
        city: _p!.city,
        state: _p!.state,
        specialty: specialty.filterLabel,
      );
      doctor.npi = result.npi;
      doctor.verificationStatus = result.status;
      doctor.npiCandidates = result.candidates;
      doctor.verifiedAt = result.isVerified ? DateTime.now() : null;
      doctor.verifiedBy =
          result.isVerified ? result.verifiedBy ?? 'auto' : null;
      await _save();
    }

    if (result.status != 'needs_review' ||
        result.candidates.isEmpty ||
        !mounted) {
      return;
    }

    final selected = await showNpiCandidatePicker(
      context: context,
      title: 'Which provider is ${doctor.name}?',
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
    doctor.npiCandidates = result.candidates;
    doctor.verifiedAt = DateTime.now();
    doctor.verifiedBy = confirmed['verifiedBy']?.toString();
    await _save();
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove doctor?'),
        content: Text(_p!.doctors[i].name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
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
      appBar: AppBar(title: const Text("Doctors")),
      body: docs.isEmpty
          ? const Center(child: Text("No doctors added."))
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
                      if ([d.specialty, d.clinic, d.phone]
                          .any((value) => value.isNotEmpty))
                        Text([
                          if (d.specialty.isNotEmpty) d.specialty,
                          if (d.clinic.isNotEmpty) d.clinic,
                          if (d.phone.isNotEmpty) d.phone,
                        ].join(" • ")),
                      if (d.isPrimaryCareProvider) ...[
                        const SizedBox(height: 3),
                        primaryCareIndicator(),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
