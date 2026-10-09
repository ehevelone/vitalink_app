import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import '../services/secure_store.dart';
import '../services/data_repository.dart';
import '../models.dart';
import '../utils/phone_formatter.dart';

class AccountSetupScreen extends StatefulWidget {
  const AccountSetupScreen({super.key});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _loading = false;

  Future<void> _completeSetup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final store = SecureStore();
    final repo = DataRepository();

    // Save identity info
    await store.setBool('setupDone', true);
    await store.setString('role', 'user');
    await store.setString('username', _usernameCtrl.text.trim());
    await store.setString('password', _passwordCtrl.text.trim());
    await store.setString('profileName', _nameCtrl.text.trim());
    await store.setString('profilePhone', _phoneCtrl.text.trim());

    // 🔥 CREATE LOCAL MEDICAL PROFILE
    final newProfile = Profile(
      fullName: _nameCtrl.text.trim(),
      userPhone: _phoneCtrl.text.trim(), // ✅ FIXED
      meds: [],
      doctors: [],
      insurances: [],
    );

    await repo.addProfile(newProfile);

    if (!mounted) return;

    setState(() => _loading = false);
    Navigator.pushReplacementNamed(context, '/menu');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).accountSetup)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).username),
                  validator: (v) => v == null || v.isEmpty
                      ? AppStrings.of(context).enterUsername
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).password),
                  validator: (v) => v == null || v.length < 6
                      ? AppStrings.of(context).minSixChars
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).confirmPassword),
                  validator: (v) => v != _passwordCtrl.text
                      ? AppStrings.of(context).passwordsDontMatchCurly
                      : null,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).fullName),
                  validator: (v) => v == null || v.isEmpty
                      ? AppStrings.of(context).enterYourName
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    PhoneNumberFormatter(),
                  ],
                  decoration:
                      InputDecoration(labelText: AppStrings.of(context).phone),
                  validator: (v) => v == null || v.isEmpty
                      ? AppStrings.of(context).enterYourPhone
                      : null,
                ),
                const SizedBox(height: 24),
                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _completeSetup,
                        child: Text(AppStrings.of(context).finishSetup),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
