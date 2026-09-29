// lib/screens/profile_user_screen.dart
import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../utils/phone_formatter.dart';

String profileValueOrFallback(String? profileValue, String fallback) {
  final value = profileValue?.trim() ?? '';
  return value.isNotEmpty ? value : fallback;
}

String _mapText(Map<String, dynamic> values, String key) {
  return values[key]?.toString().trim() ?? '';
}

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
  bool _isVeteran = false;
  bool _usesVaHealthcare = false;

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
  }

  Future<void> _loadLocalProfile() async {
    final store = SecureStore();

    final userId = await store.getString('userId') ?? '';
    final savedEmail = await store.getString('userEmail') ?? "";
    final savedName = await store.getString('profileName') ?? "";
    final savedPhone = await store.getString('profilePhone') ?? "";

    final savedAddress = await store.getString('profileAddress') ?? "";
    final savedCity = await store.getString('profileCity') ?? "";
    final savedState = await store.getString('profileState') ?? "";
    final savedZip = await store.getString('profileZip') ?? "";

    final repo = DataRepository();
    final profile = await repo.loadProfile();

    var remote = <String, dynamic>{};
    if (userId.isNotEmpty) {
      try {
        final response = await ApiService.getUserDemographics(
          userId: userId,
          profileId: profile.id,
        );
        if (response['success'] == true && response['demographics'] is Map) {
          remote = Map<String, dynamic>.from(response['demographics'] as Map);
        }
      } catch (error) {
        debugPrint('Demographic recovery unavailable: $error');
      }
    }

    final email = profileValueOrFallback(
      savedEmail,
      _mapText(remote, 'email'),
    );
    final name = profileValueOrFallback(
      profile.fullName,
      profileValueOrFallback(savedName, _mapText(remote, 'fullName')),
    );
    final phone = profileValueOrFallback(
      profile.userPhone,
      profileValueOrFallback(savedPhone, _mapText(remote, 'userPhone')),
    );
    final dob = profileValueOrFallback(profile.dob, _mapText(remote, 'dob'));
    final address = profileValueOrFallback(
      profile.address,
      profileValueOrFallback(savedAddress, _mapText(remote, 'address')),
    );
    final city = profileValueOrFallback(
      profile.city,
      profileValueOrFallback(savedCity, _mapText(remote, 'city')),
    );
    final state = profileValueOrFallback(
      profile.state,
      profileValueOrFallback(savedState, _mapText(remote, 'state')),
    );
    final zip = profileValueOrFallback(
      profile.zip,
      profileValueOrFallback(savedZip, _mapText(remote, 'zip')),
    );
    final isVeteran = profile.isVeteran || remote['isVeteran'] == true;
    final usesVaHealthcare =
        profile.usesVaHealthcare || remote['usesVaHealthcare'] == true;

    final needsProfileRepair =
        profile.fullName.trim().isEmpty && name.isNotEmpty ||
        profile.userPhone.trim().isEmpty && phone.isNotEmpty ||
        (profile.dob?.trim().isEmpty ?? true) && dob.isNotEmpty ||
        (profile.address?.trim().isEmpty ?? true) && address.isNotEmpty ||
        (profile.city?.trim().isEmpty ?? true) && city.isNotEmpty ||
        (profile.state?.trim().isEmpty ?? true) && state.isNotEmpty ||
        (profile.zip?.trim().isEmpty ?? true) && zip.isNotEmpty ||
        profile.isVeteran != isVeteran ||
        profile.usesVaHealthcare != usesVaHealthcare;

    if (needsProfileRepair) {
      if (profile.fullName.trim().isEmpty) profile.fullName = name;
      if (profile.userPhone.trim().isEmpty) profile.userPhone = phone;
      if (profile.dob?.trim().isEmpty ?? true) profile.dob = dob;
      if (profile.address?.trim().isEmpty ?? true) profile.address = address;
      if (profile.city?.trim().isEmpty ?? true) profile.city = city;
      if (profile.state?.trim().isEmpty ?? true) profile.state = state;
      if (profile.zip?.trim().isEmpty ?? true) profile.zip = zip;
      profile.isVeteran = isVeteran;
      profile.usesVaHealthcare = isVeteran && usesVaHealthcare;
      profile.updatedAt = DateTime.now();
      await repo.saveProfile(profile, publishUpdate: false);
    }

    if (email.isNotEmpty) await store.setString('userEmail', email);
    if (name.isNotEmpty) await store.setString('profileName', name);
    if (phone.isNotEmpty) await store.setString('profilePhone', phone);
    if (address.isNotEmpty) await store.setString('profileAddress', address);
    if (city.isNotEmpty) await store.setString('profileCity', city);
    if (state.isNotEmpty) await store.setString('profileState', state);
    if (zip.isNotEmpty) await store.setString('profileZip', zip);

    if (!mounted) return;

    setState(() {
      _currentEmail = email;
      _emailCtrl.text = email;
      _nameCtrl.text = name;
      _phoneCtrl.text = phone;
      _dobCtrl.text = dob;

      _addressCtrl.text = address;
      _cityCtrl.text = city;
      _stateCtrl.text = state;
      _zipCtrl.text = zip;
      _isVeteran = isVeteran;
      _usesVaHealthcare = isVeteran && usesVaHealthcare;
    });
  }

  Future<void> _changeVeteranStatus(bool value) async {
    if (value) {
      setState(() => _isVeteran = true);
      return;
    }

    final removeStatus = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Veteran status?'),
        content: const Text(
          'This will also remove the VA health care selection and VA emergency notice from this profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Veteran Status'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (removeStatus == true && mounted) {
      setState(() {
        _isVeteran = false;
        _usesVaHealthcare = false;
      });
    }
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
        if (!mounted) return;
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
      final profile = await repo.loadProfile();

      profile.fullName = newName;
      profile.userPhone = newPhone;
      profile.dob = newDob; // ✅ FIXED
      profile.address = newAddress;
      profile.city = newCity;
      profile.state = newState;
      profile.zip = newZip;
      profile.isVeteran = _isVeteran;
      profile.usesVaHealthcare = _isVeteran && _usesVaHealthcare;
      profile.updatedAt = DateTime.now();

      await repo.saveProfile(profile);

      if (newPassword.isNotEmpty) {
        await store.setString('userPassword', newPassword);
      }

      _currentEmail = newEmail;

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Profile updated ✅")));

      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                    if (!context.mounted) return;
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
                  decoration: const InputDecoration(
                    labelText: "Address Line 1",
                  ),
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

                const SizedBox(height: 16),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isVeteran,
                  onChanged: _changeVeteranStatus,
                  title: const Text("Are you a Veteran?"),
                  activeThumbColor: Colors.blue,
                ),
                if (_isVeteran)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _usesVaHealthcare,
                    onChanged: (value) =>
                        setState(() => _usesVaHealthcare = value),
                    title: const Text("Do you use VA health care?"),
                    activeThumbColor: Colors.blue,
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
