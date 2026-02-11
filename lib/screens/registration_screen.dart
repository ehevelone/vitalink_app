import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../models.dart';
import '../widgets/password_rules.dart';
import '../widgets/safe_bottom_button.dart';
import 'qr_scanner_screen.dart';

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final b = StringBuffer();
    for (int i = 0; i < digits.length && i < 10; i++) {
      if (i == 0) b.write('(');
      if (i == 3) b.write(')');
      if (i == 6) b.write('-');
      b.write(digits[i]);
    }
    return TextEditingValue(
      text: b.toString(),
      selection: TextSelection.collapsed(offset: b.length),
    );
  }
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _agentCodeCtrl = TextEditingController();

  bool _loading = false;

  Future<void> _scanQr() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          onScanned: (value) {
            setState(() => _agentCodeCtrl.text = value.trim());
          },
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final store = SecureStore();
      final repo = DataRepository(store);

      // 🔎 Resolve agent via QR / agent code
      final code = _agentCodeCtrl.text.trim();
      final res = await ApiService.resolveAgentByCode(code);

      if (res['success'] != true || res['agent'] == null) {
        throw Exception("Invalid or inactive agent code");
      }

      final agent = res['agent'];

      // Load or create profile
      final profile = await repo.loadProfile() ?? Profile();

      profile.fullName = _nameCtrl.text.trim();
      profile.emergency =
          profile.emergency.copyWith(phone: _phoneCtrl.text.trim());

      // ✅ Agent info belongs on PROFILE
      profile.agentId = agent['id'];
      profile.agentName = agent['name'];
      profile.agentEmail = agent['email'];
      profile.agentPhone = agent['phone'];

      profile.registered = true;
      profile.updatedAt = DateTime.now();

      await repo.saveProfile(profile);

      // 🔐 Session / startup flags
      await store.setBool('loggedIn', true);
      await store.setString('role', 'user');

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/menu');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Registration failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("User Registration")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Full Name"),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: "Phone"),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password"),
                validator: (v) =>
                    v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 8),
              PasswordRules(controller: _passwordCtrl),

              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: "Confirm Password"),
                validator: (v) =>
                    v != _passwordCtrl.text ? "Passwords don’t match" : null,
              ),

              const SizedBox(height: 16),
              TextFormField(
                controller: _agentCodeCtrl,
                decoration: InputDecoration(
                  labelText: "Agent Code",
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code),
                    onPressed: _scanQr,
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Agent code required" : null,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeBottomButton(
        label: "Complete Registration",
        icon: Icons.check,
        loading: _loading,
        onPressed: _register,
      ),
    );
  }
}
