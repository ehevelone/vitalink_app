import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;
  bool _syncing = false;

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
    if (_p == null) return;

    _p!.updatedAt = DateTime.now();
    await _repo.saveProfile(_p!);

    if (mounted) {
      setState(() => _syncing = true);
    }

    await ApiService.syncProfilesToServer();

    if (mounted) {
      setState(() => _syncing = false);
    }
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour12 = local.hour == 0
        ? 12
        : local.hour > 12
            ? local.hour - 12
            : local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';

    return '$month/$day/$year $hour12:$minute $suffix';
  }

  Future<void> _addOrEdit({
    UserAppointment? existing,
    int? index,
  }) async {
    DateTime selected = existing?.appointmentAt ?? DateTime.now();
    const addNewDoctorValue = '__add_new_doctor__';
    final doctors = List<Doctor>.from(_p?.doctors ?? [])
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final existingDoctorIndex = doctors.indexWhere(
      (doctor) =>
          doctor.name.toLowerCase().trim() ==
          (existing?.doctorName ?? '').toLowerCase().trim(),
    );
    int? selectedDoctorIndex = existingDoctorIndex >= 0
        ? existingDoctorIndex
        : existing == null && doctors.isNotEmpty
            ? 0
            : null;
    bool addingNewDoctor =
        doctors.isEmpty || (existing != null && selectedDoctorIndex == null);
    final doctorName = TextEditingController(
      text: addingNewDoctor ? existing?.doctorName ?? '' : '',
    );
    final initialDoctorIndex = selectedDoctorIndex;
    final specialty = TextEditingController(
      text: existing?.specialty ??
          (initialDoctorIndex == null
              ? ''
              : doctors[initialDoctorIndex].specialty),
    );
    final notes = TextEditingController(text: existing?.notes ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Add Appointment' : 'Edit Appointment',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: addingNewDoctor
                      ? addNewDoctorValue
                      : selectedDoctorIndex == null
                          ? null
                          : 'doctor_$selectedDoctorIndex',
                  decoration: const InputDecoration(
                    labelText: 'Doctor',
                  ),
                  items: [
                    ...doctors.asMap().entries.map(
                      (entry) => DropdownMenuItem<String>(
                        value: 'doctor_${entry.key}',
                        child: Text(
                          entry.value.specialty.isEmpty
                              ? entry.value.name
                              : '${entry.value.name} - ${entry.value.specialty}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const DropdownMenuItem<String>(
                      value: addNewDoctorValue,
                      child: Text('Add New Doctor'),
                    ),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      addingNewDoctor = value == addNewDoctorValue;
                      selectedDoctorIndex = null;

                      if (addingNewDoctor) {
                        doctorName.clear();
                        specialty.clear();
                        return;
                      }

                      final indexText = value?.replaceFirst('doctor_', '');
                      final index = int.tryParse(indexText ?? '');

                      if (index != null &&
                          index >= 0 &&
                          index < doctors.length) {
                        selectedDoctorIndex = index;
                        specialty.text = doctors[index].specialty;
                      }
                    });
                  },
                ),
                if (addingNewDoctor) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: doctorName,
                    decoration: const InputDecoration(
                      labelText: 'Doctor Name',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: specialty,
                  decoration: const InputDecoration(
                    labelText: 'Specialty',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: const Text('Date / Time'),
                  subtitle: Text(_dateLabel(selected)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: dialogContext,
                      initialDate: selected,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );

                    if (date == null) return;

                    final time = await showTimePicker(
                      context: dialogContext,
                      initialTime: TimeOfDay.fromDateTime(selected),
                    );

                    if (time == null) return;

                    setDialogState(() {
                      selected = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || _p == null) return;

    final chosenDoctorIndex = selectedDoctorIndex;
    final selectedDoctor =
        chosenDoctorIndex == null ? null : doctors[chosenDoctorIndex];
    final resolvedDoctorName = addingNewDoctor
        ? doctorName.text.trim()
        : selectedDoctor?.name.trim() ?? '';
    final resolvedSpecialty = specialty.text.trim();

    final appointment = UserAppointment(
      doctorName: resolvedDoctorName,
      specialty: specialty.text.trim(),
      appointmentAt: selected,
      notes: notes.text.trim(),
      updatedAt: DateTime.now(),
    );

    if (appointment.doctorName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doctor name is required')),
      );
      return;
    }

    setState(() {
      if (addingNewDoctor) {
        final alreadyExists = _p!.doctors.any(
          (doctor) =>
              doctor.name.toLowerCase().trim() ==
              resolvedDoctorName.toLowerCase().trim(),
        );

        if (!alreadyExists) {
          _p!.doctors.add(
            Doctor(
              name: resolvedDoctorName,
              specialty: resolvedSpecialty,
            ),
          );
        }
      } else if (selectedDoctor != null && resolvedSpecialty.isNotEmpty) {
        selectedDoctor.specialty = resolvedSpecialty;
      }

      if (existing == null) {
        _p!.appointments.add(appointment);
      } else {
        _p!.appointments[index!] = appointment;
      }
      _p!.appointments.sort(
        (a, b) => a.appointmentAt.compareTo(b.appointmentAt),
      );
    });

    await _save();
  }

  Future<void> _delete(int index) async {
    if (_p == null) return;

    final item = _p!.appointments[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove appointment?'),
        content: Text(
          '${item.doctorName}\n${_dateLabel(item.appointmentAt)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _p!.appointments.removeAt(index));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final appointments = List<UserAppointment>.from(_p?.appointments ?? [])
      ..sort((a, b) => a.appointmentAt.compareTo(b.appointmentAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: appointments.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No appointments added.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: appointments.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = appointments[index];
                final originalIndex = _p?.appointments.indexOf(item) ?? -1;
                final subtitle = [
                  if (item.specialty.isNotEmpty) item.specialty,
                  _dateLabel(item.appointmentAt),
                  if (item.notes.isNotEmpty) item.notes,
                ].join('\n');

                return ListTile(
                  leading: const Icon(Icons.event_available),
                  title: Text(
                    item.doctorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(subtitle),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: originalIndex < 0
                        ? null
                        : () => _delete(originalIndex),
                  ),
                  onTap: originalIndex < 0
                      ? null
                      : () => _addOrEdit(existing: item, index: originalIndex),
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
