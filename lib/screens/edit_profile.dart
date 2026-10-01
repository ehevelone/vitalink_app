import 'package:flutter/material.dart';
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

  bool _organDonor = false;

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
      _contactCtrl.text =
          contacts.isNotEmpty ? contacts.first.name : e.contact;
      _phoneCtrl.text =
          contacts.isNotEmpty ? contacts.first.phone : e.phone;
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

      _organDonor = e.organDonor;
    });
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
      ),
    );

    await _repo.saveProfile(_p!);

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

      final contact = contactsToText.first;
      final agentLine = (agentName.isNotEmpty && agentPhone.isNotEmpty)
          ? "\n\nVitaLink was provided through ${_p!.fullName}'s insurance agent:\n"
              "$agentName\n"
              "$agentPhone\n"
              "Contact the agent if you have questions or would like more information."
          : "";

      final message =
          "Hi ${contact.name},\n\n"
          "${_p!.fullName} selected you as an emergency contact in VitaLink.\n\n"
          "VitaLink stores important health information that can help in an emergency if someone is unconscious or unable to communicate."
          "$agentLine\n\n"
          "More information: https://myvitalink.app";

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
      appBar: AppBar(title: const Text("Edit Profile")),
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
                decoration: const InputDecoration(
                  labelText: "Full Name (First & Last)",
                  hintText: "First and Last Name",
                  helperText: "Required for emergency identification",
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "Required";
                  }
                  if (!_validFullName(v)) {
                    return "Enter first & last name";
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
                    decoration: const InputDecoration(
                      labelText: "Date of Birth (MM/DD/YYYY)",
                      suffixIcon: Icon(Icons.calendar_today),
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
                    decoration: const InputDecoration(labelText: "Blood Type"),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactCtrl,
                decoration:
                    const InputDecoration(labelText: "Emergency Contact"),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "Required";
                  }
                  if (!_validFullName(v)) {
                    return "Enter full name";
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
                decoration: const InputDecoration(
                  labelText: "Emergency Phone",
                ),
                validator: (v) {
                  final digits = v?.replaceAll(RegExp(r'\D'), '') ?? "";
                  if (digits.length != 10) {
                    return "Enter valid phone";
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
                        "Emergency Contact ${i + 2}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: "Remove emergency contact",
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeEmergencyContact(i),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _extraContactCtrls[i],
                  decoration:
                      const InputDecoration(labelText: "Emergency Contact"),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return "Required";
                    }
                    if (!_validFullName(v)) {
                      return "Enter full name";
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
                  decoration: const InputDecoration(
                    labelText: "Emergency Phone",
                  ),
                  validator: (v) {
                    final digits = v?.replaceAll(RegExp(r'\D'), '') ?? "";
                    if (digits.length != 10) {
                      return "Enter valid phone";
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
                  label: const Text("Add Another Emergency Contact"),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _allergiesCtrl,
                    decoration: const InputDecoration(labelText: "Allergies"),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _conditionsCtrl,
                    decoration: const InputDecoration(labelText: "Conditions"),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _implantsCtrl,
                    decoration:
                        const InputDecoration(labelText: "Implanted Devices"),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  TextField(
                    controller: _proceduresCtrl,
                    decoration:
                        const InputDecoration(labelText: "Major Procedures"),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                value: _organDonor,
                onChanged: (v) => setState(() => _organDonor = v),
                title: const Text("Organ Donor"),
                activeThumbColor: Colors.red,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
