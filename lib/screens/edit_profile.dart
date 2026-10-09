import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../utils/phone_formatter.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _bloodCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final List<TextEditingController> _extraContactCtrls = [];
  final List<TextEditingController> _extraPhoneCtrls = [];
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();

  final _implantsCtrl = TextEditingController();
  final _proceduresCtrl = TextEditingController();
  final _dnrPolstLocationCtrl = TextEditingController();

  bool _organDonor = false;
  bool _dnrPolstOnFile = false;
  bool _isVeteran = false;
  bool _usesVaHealthcare = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _bloodCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _implantsCtrl.dispose();
    _proceduresCtrl.dispose();
    _dnrPolstLocationCtrl.dispose();
    for (final controller in _extraContactCtrls) {
      controller.dispose();
    }
    for (final controller in _extraPhoneCtrls) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final profile = await _repo.loadProfile();
    if (!mounted) return;

    setState(() {
      _p = profile;
      _loading = false;

      final e = _p!.emergency;
      _nameCtrl.text = _p!.fullName;
      _dobCtrl.text = _p!.dob ?? '';
      _bloodCtrl.text = e.bloodType;
      final contacts = e.effectiveContacts;
      _contactCtrl.text = contacts.isNotEmpty ? contacts.first.name : e.contact;
      _phoneCtrl.text = contacts.isNotEmpty ? contacts.first.phone : e.phone;
      _extraContactCtrls.clear();
      _extraPhoneCtrls.clear();
      for (final contact in contacts.skip(1)) {
        _extraContactCtrls.add(TextEditingController(text: contact.name));
        _extraPhoneCtrls.add(TextEditingController(text: contact.phone));
      }
      _allergiesCtrl.text = e.allergies;
      _conditionsCtrl.text = e.conditions;

      _implantsCtrl.text = e.implants;
      _proceduresCtrl.text = e.procedures;
      _dnrPolstLocationCtrl.text = e.dnrPolstLocation;

      _organDonor = e.organDonor;
      _dnrPolstOnFile = e.dnrPolstOnFile;
      _isVeteran = _p!.isVeteran;
      _usesVaHealthcare = _p!.usesVaHealthcare;
    });
  }

  Future<void> _changeVeteranStatus(bool value) async {
    if (value) {
      setState(() => _isVeteran = true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).removeVeteranStatus),
        content: Text(
          AppStrings.of(context).removeVeteranStatusBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.of(context).keepVeteranStatus),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.of(context).remove),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _isVeteran = false;
        _usesVaHealthcare = false;
      });
    }
  }

  bool _validFullName(String v) {
    final parts = v.trim().split(" ").where((p) => p.isNotEmpty).toList();
    return parts.length >= 2 && parts[0].length >= 2 && parts[1].length >= 2;
  }

  Future<void> _save() async {
    if (_p == null) return;

    if (!_formKey.currentState!.validate()) return;

    // 🔥 FIX: capture ORIGINAL values BEFORE mutation
    final originalContacts = _p!.emergency.effectiveContacts;
    final emergencyContacts = _buildEmergencyContacts();
    final contactsToText = _contactsNeedingText(
      originalContacts,
      emergencyContacts,
    );

    setState(() => _loading = true);

    _p = _p!.copyWith(
      fullName: _nameCtrl.text.trim(),
      dob: _dobCtrl.text.trim(),
      isVeteran: _isVeteran,
      usesVaHealthcare: _isVeteran && _usesVaHealthcare,
      emergency: _p!.emergency.copyWith(
        bloodType: _bloodCtrl.text.trim(),
        contact: _contactCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        contacts: emergencyContacts,
        allergies: _allergiesCtrl.text.trim(),
        conditions: _conditionsCtrl.text.trim(),
        implants: _implantsCtrl.text.trim(),
        procedures: _proceduresCtrl.text.trim(),
        organDonor: _organDonor,
        dnrPolstOnFile: _dnrPolstOnFile,
        dnrPolstLocation:
            _dnrPolstOnFile ? _dnrPolstLocationCtrl.text.trim() : '',
      ),
    );

    await _repo.saveProfile(_p!);
    await ApiService.syncProfilesToServer();

    if (!mounted) return;

    // 🔥 FIXED CONDITION
    if (contactsToText.isNotEmpty) {
      String agentName = "";
      String agentPhone = "";

      try {
        final userEmail = await AppState.getEmail();
        if (userEmail != null && userEmail.isNotEmpty) {
          final res = await ApiService.getUserAgent(userEmail);
          if (res["success"] == true && res["agent"] != null) {
            agentName = res["agent"]["name"] ?? "";
            agentPhone = res["agent"]["phone"] ?? "";
          }
        }
      } catch (_) {}

      if (!mounted) return;
      final strings = AppStrings.of(context);
      final contact = contactsToText.first;
      final agentLine = (agentName.isNotEmpty && agentPhone.isNotEmpty)
          ? strings.emergencyContactTextAgent(
              _p!.fullName, agentName, agentPhone)
          : "";

      final message =
          '${strings.emergencyContactTextIntro(contact.name, _p!.fullName)}'
          '$agentLine\n\n'
          '${strings.emergencyContactTextMoreInfo()}';

      await _openEmergencyContactText(contact, message);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  List<EmergencyContact> _buildEmergencyContacts() {
    final contacts = [
      EmergencyContact(
        name: _contactCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      ),
      for (var i = 0; i < _extraContactCtrls.length; i++)
        EmergencyContact(
          name: _extraContactCtrls[i].text.trim(),
          phone: _extraPhoneCtrls[i].text.trim(),
        ),
    ];

    return contacts.where((contact) => contact.hasDetails).toList();
  }

  List<EmergencyContact> _contactsNeedingText(
    List<EmergencyContact> originalContacts,
    List<EmergencyContact> savedContacts,
  ) {
    final changedContacts = <EmergencyContact>[];

    for (var i = 0; i < savedContacts.length; i++) {
      final saved = savedContacts[i];
      final savedPhone = _phoneDigits(saved.phone);
      if (savedPhone.length != 10) continue;

      final original = i < originalContacts.length
          ? originalContacts[i]
          : EmergencyContact();

      if (savedPhone != _phoneDigits(original.phone) ||
          saved.name.trim() != original.name.trim()) {
        changedContacts.add(saved);
      }
    }

    return changedContacts;
  }

  String _phoneDigits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  Future<void> _openEmergencyContactText(
    EmergencyContact contact,
    String message,
  ) async {
    final smsUri = Uri.parse(
      "sms:${_phoneDigits(contact.phone)}?body=${Uri.encodeComponent(message)}",
    );

    await launchUrl(
      smsUri,
      mode: LaunchMode.externalApplication,
    );
  }

  void _addEmergencyContact() {
    setState(() {
      _extraContactCtrls.add(TextEditingController());
      _extraPhoneCtrls.add(TextEditingController());
    });
  }

  void _removeEmergencyContact(int index) {
    setState(() {
      _extraContactCtrls.removeAt(index).dispose();
      _extraPhoneCtrls.removeAt(index).dispose();
    });
  }

  Future<void> _pickDob() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDate: DateTime(1990),
    );

    if (date != null) {
      _dobCtrl.text = "${date.month.toString().padLeft(2, '0')}/"
          "${date.day.toString().padLeft(2, '0')}/"
          "${date.year}";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).editProfile)),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(context).viewInsets.bottom + 40,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).fullNameFirstLast,
                  hintText: AppStrings.of(context).firstAndLastName,
                  helperText: AppStrings.of(context).requiredForEmergencyId,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return AppStrings.of(context).requiredField;
                  }
                  if (!_validFullName(v)) {
                    return AppStrings.of(context).enterFirstLastName;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _dobCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).dobMmDdYyyy,
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    onTap: _pickDob,
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _bloodCtrl,
                    decoration: InputDecoration(
                        labelText: AppStrings.of(context).bloodType),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).emergencyContactLabel),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return AppStrings.of(context).requiredField;
                  }
                  if (!_validFullName(v)) {
                    return AppStrings.of(context).enterFullName;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  PhoneNumberFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).emergencyPhone,
                ),
                validator: (v) {
                  final digits = v?.replaceAll(RegExp(r'\D'), '') ?? "";
                  if (digits.length != 10) {
                    return AppStrings.of(context).enterValidPhone;
                  }
                  return null;
                },
              ),
              for (var i = 0; i < _extraContactCtrls.length; i++) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.of(context)
                            .emergencyContactNumberTitle(i + 2),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.of(context).removeEmergencyContact,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeEmergencyContact(i),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _extraContactCtrls[i],
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).emergencyContactLabel),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return AppStrings.of(context).requiredField;
                    }
                    if (!_validFullName(v)) {
                      return AppStrings.of(context).enterFullName;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _extraPhoneCtrls[i],
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    PhoneNumberFormatter(),
                  ],
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).emergencyPhone,
                  ),
                  validator: (v) {
                    final digits = v?.replaceAll(RegExp(r'\D'), '') ?? "";
                    if (digits.length != 10) {
                      return AppStrings.of(context).enterValidPhone;
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addEmergencyContact,
                  icon: const Icon(Icons.add_circle_outline),
                  label:
                      Text(AppStrings.of(context).addAnotherEmergencyContact),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _allergiesCtrl,
                    decoration: InputDecoration(
                        labelText: AppStrings.of(context).allergies),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _conditionsCtrl,
                    decoration: InputDecoration(
                        labelText: AppStrings.of(context).conditions),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _implantsCtrl,
                    decoration: InputDecoration(
                        labelText: AppStrings.of(context).implantedDevices),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _proceduresCtrl,
                    decoration: InputDecoration(
                        labelText: AppStrings.of(context).majorProcedures),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                value: _isVeteran,
                onChanged: _changeVeteranStatus,
                title: Text(AppStrings.of(context).veteran),
                activeThumbColor: Colors.blue,
              ),
              if (_isVeteran)
                SwitchListTile(
                  value: _usesVaHealthcare,
                  onChanged: (value) =>
                      setState(() => _usesVaHealthcare = value),
                  title: Text(AppStrings.of(context).useVaHealthCare),
                  activeThumbColor: Colors.blue,
                ),
              SwitchListTile(
                value: _organDonor,
                onChanged: (v) => setState(() => _organDonor = v),
                title: Text(AppStrings.of(context).organDonor),
                activeThumbColor: Colors.red,
              ),
              SwitchListTile(
                value: _dnrPolstOnFile,
                onChanged: (value) =>
                    setState(() => _dnrPolstOnFile = value),
                title: Text(AppStrings.of(context).dnrPolstOnFile),
                activeThumbColor: Colors.red,
              ),
              if (_dnrPolstOnFile) ...[
                TextFormField(
                  controller: _dnrPolstLocationCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).signedFormLocation,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? AppStrings.of(context).enterSignedFormLocation
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.of(context).dnrPolstDisclaimer,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(AppStrings.of(context).save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
