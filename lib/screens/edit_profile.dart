import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();

  final _implantsCtrl = TextEditingController();
  final _proceduresCtrl = TextEditingController();

  bool _organDonor = false;

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
      _p = profile ?? Profile();
      _loading = false;

      if (_p != null) {
        final e = _p!.emergency;
        _nameCtrl.text = _p!.fullName;
        _dobCtrl.text = _p!.dob ?? '';
        _bloodCtrl.text = e.bloodType;
        _contactCtrl.text = e.contact;
        _phoneCtrl.text = e.phone;
        _allergiesCtrl.text = e.allergies;
        _conditionsCtrl.text = e.conditions;

        _implantsCtrl.text = e.implants;
        _proceduresCtrl.text = e.procedures;

        _organDonor = e.organDonor;
      }
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
    final originalPhone =
        _p!.emergency.phone.replaceAll(RegExp(r'\D'), '');
    final originalContact = _p!.emergency.contact;

    final newPhone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final newContact = _contactCtrl.text.trim();

    setState(() => _loading = true);

    _p = _p!.copyWith(
      fullName: _nameCtrl.text.trim(),
      dob: _dobCtrl.text.trim(),
      emergency: _p!.emergency.copyWith(
        bloodType: _bloodCtrl.text.trim(),
        contact: _contactCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
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
    if (newPhone.length == 10 &&
        (newPhone != originalPhone ||
         newContact != originalContact)) {

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

      final agentLine = (agentName.isNotEmpty && agentPhone.isNotEmpty)
          ? "\n\nTheir insurance agent is $agentName at $agentPhone."
          : "\n\nOR contact — their insurance agent _______________.";

      final message =
          "You have been added as ${_p!.fullName}'s emergency contact in the VitaLink app. "
          "Learn more at https://myvitalink.app — OR contact — their insurance agent.$agentLine";

      final smsUri = Uri.parse(
        "sms:$newPhone?body=${Uri.encodeComponent(message)}",
      );

      await launchUrl(
        smsUri,
        mode: LaunchMode.externalApplication,
      );
    }

    Navigator.pop(context);
  }

  Future<void> _pickDob() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDate: DateTime(1990),
    );

    if (date != null) {
      _dobCtrl.text =
          "${date.month.toString().padLeft(2, '0')}/"
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

              TextField(
                controller: _dobCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Date of Birth (MM/DD/YYYY)",
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                onTap: _pickDob,
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _bloodCtrl,
                decoration: const InputDecoration(labelText: "Blood Type"),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _contactCtrl,
                decoration: const InputDecoration(labelText: "Emergency Contact"),
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
              const SizedBox(height: 12),

              TextField(
                controller: _allergiesCtrl,
                decoration: const InputDecoration(labelText: "Allergies"),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _conditionsCtrl,
                decoration: const InputDecoration(labelText: "Conditions"),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _implantsCtrl,
                decoration: const InputDecoration(labelText: "Implanted Devices"),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _proceduresCtrl,
                decoration: const InputDecoration(labelText: "Major Procedures"),
              ),
              const SizedBox(height: 24),

              SwitchListTile(
                value: _organDonor,
                onChanged: (v) => setState(() => _organDonor = v),
                title: const Text("Organ Donor"),
                activeColor: Colors.red,
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