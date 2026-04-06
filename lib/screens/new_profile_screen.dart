// lib/screens/new_profile_screen.dart
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../utils/phone_formatter.dart';

class NewProfileScreen extends StatefulWidget {
  const NewProfileScreen({super.key});

  @override
  State<NewProfileScreen> createState() => _NewProfileScreenState();
}

class _NewProfileScreenState extends State<NewProfileScreen> {
  late final DataRepository _repo;

  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _bloodCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
  }

  bool _validFullName(String v) {
    final parts = v.trim().split(" ").where((p) => p.isNotEmpty).toList();
    return parts.length >= 2 && parts[0].length >= 2 && parts[1].length >= 2;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final newProfile = Profile(
      fullName: _nameCtrl.text.trim(),
      dob: _dobCtrl.text.trim(),
      emergency: EmergencyInfo(
        contact: _contactCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        allergies: _allergiesCtrl.text.trim(),
        conditions: _conditionsCtrl.text.trim(),
        bloodType: _bloodCtrl.text.trim(),
      ),
    );

    await _repo.addProfile(newProfile);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Household Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
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
                    return "Name is required";
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
                decoration: const InputDecoration(labelText: "Blood Type (optional)"),
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
                inputFormatters: [PhoneNumberFormatter()],
                decoration: const InputDecoration(labelText: "Emergency Phone"),
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
                decoration: const InputDecoration(labelText: "Medical Conditions"),
              ),
              const SizedBox(height: 26),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Save Household Profile"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}