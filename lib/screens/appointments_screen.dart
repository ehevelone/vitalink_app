import 'dart:io';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  static const MethodChannel _calendarChannel =
      MethodChannel('com.etnaturals.vitalinkapp/calendar');

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

  String _icsDate(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  String _icsText(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\r\n', '\\n')
        .replaceAll('\n', '\\n');
  }

  Future<void> _addToDeviceCalendar(UserAppointment appointment) async {
    // Read wording before any await so it is safe to use after them.
    final strings = AppStrings.of(context);
    final start = appointment.appointmentAt.toLocal();
    final end = start.add(const Duration(hours: 1));
    final description = [
      if (appointment.specialty.isNotEmpty)
        strings.specialtyValue(
            strings.doctorSpecialtyLabel(appointment.specialty)),
      if (appointment.notes.isNotEmpty) appointment.notes,
      strings.createdFromVitaLink,
    ].join('\n');

    if (Platform.isAndroid || Platform.isIOS) {
      final opened = await _calendarChannel.invokeMethod<bool>(
            'insertEvent',
            {
              'title': strings.appointmentWith(appointment.doctorName),
              'description': description,
              'startMillis': start.millisecondsSinceEpoch,
              'endMillis': end.millisecondsSinceEpoch,
            },
          ) ??
          false;
      if (opened) return;
    }

    final fileName = appointment.doctorName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .toLowerCase();
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/${fileName.isEmpty ? 'vitalink-appointment' : fileName}.ics');
    final now = DateTime.now().toUtc();
    final ics = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//VitaLink//Appointments//EN',
      'BEGIN:VEVENT',
      'UID:${now.microsecondsSinceEpoch}@myvitalink.app',
      'DTSTAMP:${_icsDate(now)}',
      'DTSTART:${_icsDate(start)}',
      'DTEND:${_icsDate(end)}',
      'SUMMARY:${_icsText(strings.appointmentWith(appointment.doctorName))}',
      'DESCRIPTION:${_icsText(description)}',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');

    await file.writeAsString(ics);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/calendar')],
      text: strings.addAppointmentToCalendarShare,
    );
  }

  Future<void> _offerCalendarAdd(UserAppointment appointment) async {
    if (!mounted) return;

    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).addToPhoneCalendar),
        content: Text(
          '${appointment.doctorName}\n${_dateLabel(appointment.appointmentAt)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).notNow),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.calendar_month),
            label: Text(AppStrings.of(context).addToCalendar),
          ),
        ],
      ),
    );

    if (shouldAdd == true) {
      await _addToDeviceCalendar(appointment);
    }
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
            existing == null
                ? AppStrings.of(context).addAppointment
                : AppStrings.of(context).editAppointment,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: addingNewDoctor
                      ? addNewDoctorValue
                      : selectedDoctorIndex == null
                          ? null
                          : 'doctor_$selectedDoctorIndex',
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).doctor,
                  ),
                  items: [
                    ...doctors.asMap().entries.map(
                          (entry) => DropdownMenuItem<String>(
                            value: 'doctor_${entry.key}',
                            child: Text(
                              entry.value.specialty.isEmpty
                                  ? entry.value.name
                                  : '${entry.value.name} - ${AppStrings.of(context).doctorSpecialtyLabel(entry.value.specialty)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    DropdownMenuItem<String>(
                      value: addNewDoctorValue,
                      child: Text(
                        AppStrings.of(context).addNewDoctor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).doctorName,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: specialty,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).specialty,
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(AppStrings.of(context).dateTime),
                  subtitle: Text(_dateLabel(selected)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: dialogContext,
                      initialDate: selected,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );

                    if (date == null) return;
                    if (!context.mounted) return;

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
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).notes,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppStrings.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStrings.of(context).save),
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
        SnackBar(content: Text(AppStrings.of(context).doctorNameRequired)),
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
    await _offerCalendarAdd(appointment);
  }

  Future<void> _delete(int index) async {
    if (_p == null) return;

    final item = _p!.appointments[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).removeAppointment),
        content: Text(
          '${item.doctorName}\n${_dateLabel(item.appointmentAt)}',
        ),
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
        title: Text(AppStrings.of(context).appointments),
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
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  AppStrings.of(context).noAppointmentsAdded,
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
                    onPressed:
                        originalIndex < 0 ? null : () => _delete(originalIndex),
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
