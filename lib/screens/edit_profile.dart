import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../utils/phone_formatter.dart'; // ✅ ADDED

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
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
        _organDonor = e.organDonor;
      }
    });
  }

  Future<void> _save() async {
    if (_p == null) return;

    final oldPhone = _p!.emergency.phone.replaceAll(RegExp(r'\D'), '');
    final newPhone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

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
        organDonor: _organDonor,
      ),
    );

    await _repo.saveProfile(_p!);

    if (!mounted) return;

    // 🚀 If phone changed, launch SMS
    if (newPhone.length == 10 && newPhone != oldPhone) {
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
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: "Full Name"),
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

            TextField(
              controller: _contactCtrl,
              decoration: const InputDecoration(labelText: "Emergency Contact"),
            ),
            const SizedBox(height: 12),

            // ✅ FIXED PHONE FIELD
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                PhoneNumberFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: "Emergency Phone",
              ),
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
    );
  }
}