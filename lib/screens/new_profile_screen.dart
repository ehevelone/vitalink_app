import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
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

  // 🔥 ADDED
  final _implantsCtrl = TextEditingController();
  final _proceduresCtrl = TextEditingController();
  final _dnrPolstLocationCtrl = TextEditingController();
  bool _organDonor = false;
  bool _dnrPolstOnFile = false;
  bool _isVeteran = false;
  bool _usesVaHealthcare = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _bloodCtrl.dispose();
    _implantsCtrl.dispose();
    _proceduresCtrl.dispose();
    _dnrPolstLocationCtrl.dispose();
    super.dispose();
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
      _dobCtrl.text = "${date.month.toString().padLeft(2, '0')}/"
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
      isVeteran: _isVeteran,
      usesVaHealthcare: _isVeteran && _usesVaHealthcare,
      emergency: EmergencyInfo(
        contact: _contactCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        allergies: _allergiesCtrl.text.trim(),
        conditions: _conditionsCtrl.text.trim(),
        bloodType: _bloodCtrl.text.trim(),

        // 🔥 ADDED
        implants: _implantsCtrl.text.trim(),
        procedures: _proceduresCtrl.text.trim(),
        organDonor: _organDonor,
        dnrPolstOnFile: _dnrPolstOnFile,
        dnrPolstLocation:
            _dnrPolstOnFile ? _dnrPolstLocationCtrl.text.trim() : '',
      ),
    );

    await _repo.addProfile(newProfile);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).newHouseholdProfile)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
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
                    return AppStrings.of(context).nameIsRequired;
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
                        labelText: AppStrings.of(context).bloodTypeOptional),
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
                inputFormatters: [PhoneNumberFormatter()],
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).emergencyPhone),
                validator: (v) {
                  final digits = v?.replaceAll(RegExp(r'\D'), '') ?? "";
                  if (digits.length != 10) {
                    return AppStrings.of(context).enterValidPhone;
                  }
                  return null;
                },
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
                        labelText: AppStrings.of(context).medicalConditions),
                  ),
                  const Divider(height: 1),
                ],
              ),
              const SizedBox(height: 12),

              // 🔥 ADDED
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
              const SizedBox(height: 12),

              SwitchListTile(
                value: _isVeteran,
                onChanged: (value) => setState(() {
                  _isVeteran = value;
                  if (!value) _usesVaHealthcare = false;
                }),
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
              const SizedBox(height: 26),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          AppStrings.of(context).saveHouseholdProfile,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
