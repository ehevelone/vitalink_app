import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/app_state.dart';
import '../models.dart';
import '../widgets/password_rules.dart';
import '../widgets/safe_bottom_button.dart';
import '../utils/phone_formatter.dart';

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
  final _activationCodeCtrl = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  bool _activationLoaded = false;
  bool _lookupRunning = false;
  bool _argsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_argsLoaded) return;
    _argsLoaded = true;

    String? code;

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map && args['code'] != null) {
      code = args['code'].toString().trim().toUpperCase();
    }

    code ??= VitaLinkDeepLink.code?.trim().toUpperCase();

    if (code != null && code.isNotEmpty) {
      _activationCodeCtrl.text = code;

      // Clear any leftover deep link once we've consumed it here.
      if (VitaLinkDeepLink.code == code) {
        VitaLinkDeepLink.clear();
      }

      _lookupActivation();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _activationCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupActivation() async {
    if (_activationLoaded) return;
    if (_lookupRunning) return;

    final code = _activationCodeCtrl.text.trim().toUpperCase();
    if (code.length < 8) return;

    _lookupRunning = true;

    try {
      final res = await ApiService.lookupActivation(code);

      if (!mounted) return;

      if (res['success'] == true) {
        setState(() {
          _nameCtrl.text = (res['name'] ?? "").toString();
          _emailCtrl.text = (res['email'] ?? "").toString();
          _activationLoaded = true;
        });
      }
    } catch (_) {
      // intentionally quiet here
    } finally {
      _lookupRunning = false;
    }
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData('text/plain');

    if (data?.text == null) return;

    final pasted = data!.text!.trim().toUpperCase();

    setState(() {
      _activationCodeCtrl.text = pasted;
      _activationLoaded = false;
    });

    await _lookupActivation();
  }

  void _recoverCode() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Recover Activation Code"),
        content: const Text(
          "If you purchased VitaLink but lost your activation code, visit:\n\nmyvitalink.app/recover",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final repo = DataRepository();

      final code = _activationCodeCtrl.text.trim().toUpperCase();
      final email = _emailCtrl.text.trim().toLowerCase();

      final agentRes = await ApiService.resolveAgentByCode(code);

      if (agentRes['success'] != true || agentRes['agent'] == null) {
        throw Exception("Invalid or inactive activation code");
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
        platform: "mobile",
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
      if (mounted) {
        setState(() => _loading = false);
      }
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
              const Text(
                "ENTER YOUR ACTIVATION CODE",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _activationCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: "Activation Code",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: _pasteCode,
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "Activation code required" : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Full Name"),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "Name required" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: "Email"),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "Email required";
                  }
                  if (!v.contains("@")) {
                    return "Enter a valid email";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
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
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _showPassword = !_showPassword;
                      });
                    },
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 8),
              PasswordRules(controller: _passwordCtrl),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirmPassword,
                decoration: InputDecoration(
                  labelText: "Confirm Password",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _showConfirmPassword = !_showConfirmPassword;
                      });
                    },
                  ),
                ),
                validator: (v) =>
                    v != _passwordCtrl.text ? "Passwords don’t match" : null,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _recoverCode,
                  child: const Text(
                    "Lost your activation code?",
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                ),
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