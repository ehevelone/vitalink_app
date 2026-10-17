// lib/screens/profile_user_screen.dart
import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/app_state.dart';
import '../utils/phone_formatter.dart';
import 'account_correction_screen.dart';

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
  String _currentAccountName = "";
  // True when the open profile is the account holder's own. Family profiles
  // have no login, so they never change the account's email, password, name,
  // or phone.
  bool _isAccountProfile = true;
  bool _isVeteran = false;
  bool _usesVaHealthcare = false;

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
  }

  Future<void> _loadLocalProfile() async {
    final store = SecureStore();
    final userId = await store.getString('userId');
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).sessionErrorLogInAgain)),
      );
      return;
    }

    final email = await store.getString('userEmail') ?? "";

    // Registration (including agent-prepared registration) saves these on the
    // profile itself, so read the profile first and fall back to the older
    // separately stored values only when the profile field is empty.
    final repo = DataRepository();
    final profile = await repo.loadProfile();
    final isAccountProfile = await repo.isAccountProfile(profile);
    // The older separately stored values belong to the account holder only,
    // so a family member's blank field never shows the holder's details.
    Future<String> pick(String? fromProfile, String storeKey) async {
      final value = (fromProfile ?? '').trim();
      if (value.isNotEmpty || !isAccountProfile) return value;
      return (await store.getString(storeKey) ?? '').trim();
    }

    final name = await pick(profile.fullName, 'profileName');
    final phone = await pick(profile.userPhone, 'profilePhone');
    final address = await pick(profile.address, 'profileAddress');
    final city = await pick(profile.city, 'profileCity');
    final state = await pick(profile.state, 'profileState');
    final zip = await pick(profile.zip, 'profileZip');
    final dob = profile.dob ?? "";

    if (!mounted) return;

    setState(() {
      _isAccountProfile = isAccountProfile;
      _currentEmail = email;
      _currentAccountName = isAccountProfile ? name : "";
      _emailCtrl.text = email;
      _nameCtrl.text = name;
      _phoneCtrl.text = phone;
      _dobCtrl.text = dob; // ✅ FIXED

      _addressCtrl.text = address;
      _cityCtrl.text = city;
      _stateCtrl.text = state;
      _zipCtrl.text = zip;
      _isVeteran = profile.isVeteran;
      _usesVaHealthcare = profile.usesVaHealthcare;
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

  Future<void> _openAccountCorrection() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AccountCorrectionScreen(
          currentName: _currentAccountName,
          currentEmail: _currentEmail,
        ),
      ),
    );
    if (changed == true && mounted) await _loadLocalProfile();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isAccountProfile && _currentEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).sessionErrorLogInAgain)),
      );
      return;
    }

    setState(() => _loading = true);

    final store = SecureStore();
    final userId = await store.getString('userId');
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).sessionErrorLogInAgain)),
      );
      return;
    }

    final newName = _isAccountProfile
        ? _currentAccountName
        : _nameCtrl.text.trim();
    final newEmail = _currentEmail;
    final newPhone = _phoneCtrl.text.trim();
    final newDob = _dobCtrl.text.trim(); // ✅ ADDED

    final newAddress = _addressCtrl.text.trim();
    final newCity = _cityCtrl.text.trim();
    final newState = _stateCtrl.text.trim();
    final newZip = _zipCtrl.text.trim();

    final newPassword = _passwordCtrl.text.trim();

    try {
      // Only the account holder's profile updates the login account. A family
      // member's profile is saved to that profile alone.
      if (_isAccountProfile) {
        final res = await ApiService.updateUserProfile(
          userId: userId,
          currentEmail: _currentEmail,
          email: newEmail,
          name: newName,
          phone: newPhone,
          password: newPassword.isNotEmpty ? newPassword : null,
        );

        if (res['success'] != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(res['error'] ??
                    AppStrings.of(context).failedToUpdateProfile)),
          );
          return;
        }

        await store.setString('profileName', newName);
        await store.setString('profilePhone', newPhone);
        await store.setString('userEmail', newEmail);
        await AppState.setEmail(newEmail);
        if (await store.getBool('rememberMeUser') == true) {
          await store.setString('savedUserEmail', newEmail);
        }

        await store.setString('profileAddress', newAddress);
        await store.setString('profileCity', newCity);
        await store.setString('profileState', newState);
        await store.setString('profileZip', newZip);
      }

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

      if (_isAccountProfile) {
        if (newPassword.isNotEmpty) {
          await store.setString('userPassword', newPassword);
        }
        _currentEmail = newEmail;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).profileUpdatedCheck)),
      );

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
      appBar: AppBar(title: Text(AppStrings.of(context).myProfile)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Text(
                  AppStrings.of(context).userProfile,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nameCtrl,
                  readOnly: _isAccountProfile,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).fullNameFirstLast,
                    suffixIcon:
                        _isAccountProfile ? const Icon(Icons.lock) : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Family profiles have no login, so no account email here.
                if (_isAccountProfile) ...[
                  TextFormField(
                    controller: _emailCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).email,
                      suffixIcon: const Icon(Icons.lock),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('fix-name-or-email'),
                      onPressed: _openAccountCorrection,
                      icon: const Icon(Icons.edit),
                      label: Text(AppStrings.of(context).fixNameOrEmail),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],

                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneNumberFormatter()],
                  decoration:
                      InputDecoration(labelText: AppStrings.of(context).phone),
                ),
                const SizedBox(height: 12),

                // ✅ DOB FIELD ADDED
                TextFormField(
                  controller: _dobCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: "DOB",
                    hintText: AppStrings.of(context).dateHint,
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
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).addressLine1),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _cityCtrl,
                  decoration:
                      InputDecoration(labelText: AppStrings.of(context).city),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _stateCtrl,
                  decoration:
                      InputDecoration(labelText: AppStrings.of(context).state),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _zipCtrl,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).zipCode),
                ),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isVeteran,
                  onChanged: _changeVeteranStatus,
                  title: Text(AppStrings.of(context).areYouVeteran),
                ),
                if (_isVeteran)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _usesVaHealthcare,
                    onChanged: (value) =>
                        setState(() => _usesVaHealthcare = value),
                    title: Text(AppStrings.of(context).useVaHealthCare),
                  ),

                const SizedBox(height: 24),

                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: Text(AppStrings.of(context).saveChanges),
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
