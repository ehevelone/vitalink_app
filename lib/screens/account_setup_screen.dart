import 'package:flutter/material.dart';
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
      phone: _phoneCtrl.text.trim(),
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
      appBar: AppBar(title: const Text("Account Setup")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(labelText: "Username"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Enter a username" : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password"),
                  validator: (v) =>
                      v == null || v.length < 6 ? "Min 6 characters" : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Confirm Password"),
                  validator: (v) =>
                      v != _passwordCtrl.text ? "Passwords don’t match" : null,
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: "Full Name"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Enter your name" : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    PhoneNumberFormatter(),
                  ],
                  decoration: const InputDecoration(labelText: "Phone"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Enter your phone" : null,
                ),
                const SizedBox(height: 24),

                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _completeSetup,
                        child: const Text("Finish Setup"),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}