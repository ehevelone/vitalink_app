import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/app_state.dart';
import '../models.dart';
import '../widgets/password_rules.dart';
import '../widgets/safe_bottom_button.dart';
import '../utils/phone_formatter.dart'; // ✅ USE GLOBAL FORMATTER
import 'qr_scanner_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
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
      final repo = DataRepository();

      final code = _agentCodeCtrl.text.trim();
      final email = _emailCtrl.text.trim().toLowerCase();

      final agentRes = await ApiService.resolveAgentByCode(code);
      if (agentRes['success'] != true || agentRes['agent'] == null) {
        throw Exception("Invalid or inactive agent code");
      }

      final nameParts = _nameCtrl.text.trim().split(" ");
      final firstName = nameParts.first;
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(" ") : "";

      final registerRes = await ApiService.registerUser(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: _phoneCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        promoCode: code,
        platform: "android",
      );

      if (registerRes['success'] != true) {
        throw Exception(registerRes['error'] ?? "Registration failed");
      }

      final profile = await repo.loadProfile() ?? Profile();

      profile.fullName = _nameCtrl.text.trim();
      profile.emergency =
          profile.emergency.copyWith(phone: _phoneCtrl.text.trim());

      profile.registered = true;
      profile.updatedAt = DateTime.now();

      await repo.saveProfile(profile);

      await AppState.setLoggedIn(true);
      await AppState.setRole('user');
      await AppState.setEmail(email);

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
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: "Email"),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return "Email required";
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) {
                    return "Invalid email";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ✅ STANDARDIZED PHONE FIELD
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: "Phone"),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  PhoneNumberFormatter(),
                ],
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