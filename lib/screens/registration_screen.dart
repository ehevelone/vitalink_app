import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/app_state.dart';
import '../models.dart';
import '../widgets/password_rules.dart';
import '../widgets/safe_bottom_button.dart';
import '../utils/phone_formatter.dart';
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
  final _activationCodeCtrl = TextEditingController();

  bool _loading = false;

  bool _showPassword = false;
  bool _showConfirmPassword = false;

  bool _activationLoaded = false;

  bool _argsLoaded = false;

  @override
  void initState() {
    super.initState();
    _activationCodeCtrl.addListener(_lookupActivation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_argsLoaded) return;

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map && args['code'] != null) {

      final code = args['code'].toString();

      _activationCodeCtrl.text = code.toUpperCase();

      _lookupActivation();
    }

    _argsLoaded = true;
  }

  Future<void> _lookupActivation() async {

    if (_activationLoaded) return;

    final code = _activationCodeCtrl.text.trim();

    if (code.length < 8) return;

    try {

      final res = await ApiService.lookupActivation(code);

      if (res['success'] == true) {

        setState(() {
          _nameCtrl.text = res['name'] ?? "";
          _emailCtrl.text = res['email'] ?? "";
          _activationLoaded = true;
        });

      }

    } catch (_) {}

  }

  Future<void> _scanQr() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          onScanned: (value) {
            setState(() {
              _activationCodeCtrl.text = value.trim().toUpperCase();
              _activationLoaded = false;
            });
            _lookupActivation();
          },
        ),
      ),
    );
  }

  Future<void> _pasteCode() async {

    final data = await Clipboard.getData('text/plain');

    if (data != null && data.text != null) {

      setState(() {
        _activationCodeCtrl.text = data.text!.trim().toUpperCase();
        _activationLoaded = false;
      });

      _lookupActivation();
    }
  }

  void _recoverCode() {

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Recover Activation Code"),
        content: const Text(
            "If you purchased VitaLink but lost your activation code, visit:\n\nmyvitalink.app/recover"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
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

      final code = _activationCodeCtrl.text.trim();
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
                decoration: InputDecoration(
                  labelText: "Activation Code",
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      IconButton(
                        icon: const Icon(Icons.paste),
                        onPressed: _pasteCode,
                      ),

                      IconButton(
                        icon: const Icon(Icons.qr_code),
                        onPressed: _scanQr,
                      ),

                    ],
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Activation code required" : null,
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _nameCtrl,
                readOnly: true,
                decoration: const InputDecoration(labelText: "Full Name"),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _emailCtrl,
                readOnly: true,
                decoration: const InputDecoration(labelText: "Email"),
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
                      _showPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _showPassword = !_showPassword;
                      });
                    },
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Required" : null,
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
                        _showConfirmPassword =
                            !_showConfirmPassword;
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