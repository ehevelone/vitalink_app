// lib/screens/profile_user_screen.dart
import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../models.dart';
import '../utils/phone_formatter.dart';

class ProfileUserScreen extends StatefulWidget {
  const ProfileUserScreen({super.key});

  @override
  State<ProfileUserScreen> createState() => _ProfileUserScreenState();
}

class _ProfileUserScreenState extends State<ProfileUserScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController(); // ✅ already present

  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  String _currentEmail = "";

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
  }

  Future<void> _loadLocalProfile() async {
    final store = SecureStore();

    final email = await store.getString('userEmail') ?? "";
    final name = await store.getString('profileName') ?? "";
    final phone = await store.getString('profilePhone') ?? "";

    final address = await store.getString('profileAddress') ?? "";
    final city = await store.getString('profileCity') ?? "";
    final state = await store.getString('profileState') ?? "";
    final zip = await store.getString('profileZip') ?? "";

    // ✅ LOAD DOB FROM PROFILE MODEL (ONLY ONCE)
    final repo = DataRepository();
    final profile = await repo.loadProfile();
    final dob = profile?.dob ?? "";

    if (!mounted) return;

    setState(() {
      _currentEmail = email;
      _emailCtrl.text = email;
      _nameCtrl.text = name;
      _phoneCtrl.text = phone;
      _dobCtrl.text = dob; // ✅ FIXED

      _addressCtrl.text = address;
      _cityCtrl.text = city;
      _stateCtrl.text = state;
      _zipCtrl.text = zip;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (_currentEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session error. Please log in again.")),
      );
      return;
    }

    setState(() => _loading = true);

    final store = SecureStore();

    final newName = _nameCtrl.text.trim();
    final newEmail = _emailCtrl.text.trim();
    final newPhone = _phoneCtrl.text.trim();
    final newDob = _dobCtrl.text.trim(); // ✅ ADDED

    final newAddress = _addressCtrl.text.trim();
    final newCity = _cityCtrl.text.trim();
    final newState = _stateCtrl.text.trim();
    final newZip = _zipCtrl.text.trim();

    final newPassword = _passwordCtrl.text.trim();

    try {
      final res = await ApiService.updateUserProfile(
        currentEmail: _currentEmail,
        email: newEmail,
        name: newName,
        phone: newPhone,
        password: newPassword.isNotEmpty ? newPassword : null,
      );

      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'] ?? "Failed to update profile ❌")),
        );
        return;
      }

      await store.setString('profileName', newName);
      await store.setString('profilePhone', newPhone);
      await store.setString('userEmail', newEmail);

      await store.setString('profileAddress', newAddress);
      await store.setString('profileCity', newCity);
      await store.setString('profileState', newState);
      await store.setString('profileZip', newZip);

      final repo = DataRepository();
      final profile = await repo.loadProfile() ?? Profile();

      profile.fullName = newName;
      profile.userPhone = newPhone;
      profile.dob = newDob; // ✅ FIXED
      profile.address = newAddress;
      profile.city = newCity;
      profile.state = newState;
      profile.zip = newZip;
      profile.updatedAt = DateTime.now();

      await repo.saveProfile(profile);

      if (newPassword.isNotEmpty) {
        await store.setString('userPassword', newPassword);
      }

      _currentEmail = newEmail;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated ✅")),
      );

      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _validFullName(String v) {
    final parts = v.trim().split(" ").where((p) => p.isNotEmpty).toList();
    return parts.length >= 2 && parts[0].length >= 2 && parts[1].length >= 2;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose(); // ✅ FIXED

    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();

    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const Text(
                  "User Profile",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Full Name (First & Last)",
                  ),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: "Email"),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneNumberFormatter()],
                  decoration: const InputDecoration(labelText: "Phone"),
                ),
                const SizedBox(height: 12),

                // ✅ DOB FIELD ADDED
                TextFormField(
                  controller: _dobCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: "DOB",
                    hintText: "mm/dd/yyyy",
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(1970),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {
                        _dobCtrl.text =
                            "${picked.month.toString().padLeft(2, '0')}/"
                            "${picked.day.toString().padLeft(2, '0')}/"
                            "${picked.year}";
                      });
                    }
                  },
                ),

                const SizedBox(height: 12),

                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: "Address Line 1"),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(labelText: "City"),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _stateCtrl,
                  decoration: const InputDecoration(labelText: "State"),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _zipCtrl,
                  decoration: const InputDecoration(labelText: "Zip Code"),
                ),

                const SizedBox(height: 24),

                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text("Save Changes"),
                        onPressed: _saveProfile,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}