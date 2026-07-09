import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/deep_link_service.dart'; // ✅ FIX ADDED
import '../widgets/password_rules.dart';
import '../widgets/safe_bottom_button.dart';

class PhoneNumberFormatter extends TextInputFormatter {
  static String digitsForUsPhone(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 11 && digits.startsWith('1')) {
      digits = digits.substring(1);
    }

    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }

    return digits;
  }

  static String normalizedForApi(String value) {
    final digits = digitsForUsPhone(value);

    return digits.isEmpty ? "" : "+1$digits";
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = digitsForUsPhone(newValue.text);
    final b = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
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

class AgentRegistrationScreen extends StatefulWidget {
  const AgentRegistrationScreen({super.key});

  @override
  State<AgentRegistrationScreen> createState() =>
      _AgentRegistrationScreenState();
}

class _AgentRegistrationScreenState extends State<AgentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _npnCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _agencyNameCtrl = TextEditingController();
  final _agencyStreetCtrl = TextEditingController();
  final _agencyCityCtrl = TextEditingController();
  final _agencyStateCtrl = TextEditingController();
  final _agencyZipCtrl = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirm = false;

  bool _argsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_argsLoaded) return;
    _argsLoaded = true;

    String? code;

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map && args["code"] != null) {
      code = args["code"].toString();
    }

    code ??= VitaLinkDeepLink.code;

    if (code != null && code.isNotEmpty) {
      _codeCtrl.text = code;

      if (VitaLinkDeepLink.code == code) {
        VitaLinkDeepLink.clear();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _npnCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _codeCtrl.dispose();
    _agencyNameCtrl.dispose();
    _agencyStreetCtrl.dispose();
    _agencyCityCtrl.dispose();
    _agencyStateCtrl.dispose();
    _agencyZipCtrl.dispose();
    super.dispose();
  }

  String? _validatePassword(String? pw) {
    if (pw == null || pw.isEmpty) return "Enter a password";
    if (pw.length < 10) return "≥ 10 characters";
    if (!RegExp(r'[A-Z]').hasMatch(pw)) return "At least 1 uppercase";
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(pw)) {
      return "At least 1 special character";
    }
    return null;
  }

  String _normalizeCode(String value) {
    return value
        .replaceAll(RegExp(r'[\u2010-\u2015\u2212]'), '-')
        .replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')
        .trim()
        .toUpperCase();
  }

  String _normalizeEmail(String value) {
    return value.trim().toLowerCase();
  }

  String? _validateEmail(String? value) {
    final email = _normalizeEmail(value ?? "");
    if (email.isEmpty) return "Enter a valid email";

    final emailPattern = RegExp(
      r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$",
    );
    if (!emailPattern.hasMatch(email) ||
        email.contains("..") ||
        email.startsWith(".") ||
        email.endsWith(".")) {
      return "Enter a valid email";
    }

    final tld = email.split(".").last;
    const commonTypos = {
      "coim",
      "comm",
      "conm",
      "cmo",
      "ocm",
      "cpm",
      "gom",
    };
    if (commonTypos.contains(tld)) {
      return "Check the email ending. Did you mean .com?";
    }

    return null;
  }

  Future<void> _tryRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final data = await ApiService.claimAgentUnlock(
        unlockCode: _normalizeCode(_codeCtrl.text),
        email: _normalizeEmail(_emailCtrl.text),
        password: _passwordCtrl.text.trim(),
        npn: _npnCtrl.text.trim(),
        phone: PhoneNumberFormatter.normalizedForApi(_phoneCtrl.text),
        name: _nameCtrl.text.trim(),
        agencyName: _agencyNameCtrl.text.trim(),
        agencyStreet: _agencyStreetCtrl.text.trim(),
        agencyCity: _agencyCityCtrl.text.trim(),
        agencyState: _agencyStateCtrl.text.trim(),
        agencyZip: _agencyZipCtrl.text.trim(),
      );

      if (data['success'] == true) {
        final store = SecureStore();
        final email = _normalizeEmail(_emailCtrl.text);
        final password = _passwordCtrl.text.trim();

        await store.setString("agentName", _nameCtrl.text.trim());
        await store.setString("agentEmail", email);
        await store.setString("agentPhone", _phoneCtrl.text.trim());
        await store.setString(
          "agentId",
          data["agentId"]?.toString() ?? _npnCtrl.text.trim(),
        );
        await store.setString("agencyName", _agencyNameCtrl.text.trim());
        await store.setString("agencyAddress", _agencyStreetCtrl.text.trim());
        await store.setString("agencyCity", _agencyCityCtrl.text.trim());
        await store.setString("agencyState", _agencyStateCtrl.text.trim());
        await store.setString("agencyZip", _agencyZipCtrl.text.trim());

        await store.setBool("registered", true);
        await store.setBool("agentRegistered", true);
        await store.setBool("agentLoggedIn", true);
        await store.setString("role", "agent");
        await AppState.clearAuth();
        await AppState.setLoggedIn(true);
        await AppState.setRole("agent");
        await AppState.setEmail(email);

        if (data['promoCode'] != null &&
            data['promoCode'].toString().isNotEmpty) {
          await store.setString("agentPromoCode", data['promoCode']);
        }

        await store.setBool("rememberMeAgent", true);
        await store.setString("savedAgentEmail", email);
        await store.setString("savedAgentPassword", password);

        final loginData = await ApiService.loginAgent(
          email: email,
          password: password,
        );

        if (loginData["success"] == true && loginData["agent"] != null) {
          final agent = loginData["agent"];
          await store.setString("agentId", agent["id"].toString());
          await store.setString("agentEmail", agent["email"] ?? email);
          await store.setString(
            "agentName",
            agent["name"] ?? _nameCtrl.text.trim(),
          );

          final sessionToken = loginData["token"]?.toString() ?? "";
          if (sessionToken.isNotEmpty) {
            await store.setString("agentSessionToken", sessionToken);
          } else {
            await store.remove("agentSessionToken");
          }
        }

        if (!mounted) return;

        Navigator.pushReplacementNamed(context, '/agent_menu');
      } else {
        _showPopup("Registration Failed", data['error'] ?? "Unknown error ❌");
      }
    } catch (e) {
      _showPopup("Error", "Registration failed: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPopup(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Agent Registration")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Full Name"),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter your name" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: "Email"),
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _npnCtrl,
                decoration: const InputDecoration(labelText: "NPN"),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter your NPN" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: "Phone Number"),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter your phone number" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyNameCtrl,
                decoration: const InputDecoration(labelText: "Agency Name"),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter your agency name" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyStreetCtrl,
                decoration:
                    const InputDecoration(labelText: "Agency Street Address"),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter your agency address" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyCityCtrl,
                decoration: const InputDecoration(labelText: "Agency City"),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter your agency city" : null,
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _agencyStateCtrl,
                      decoration: const InputDecoration(labelText: "State"),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) =>
                          v == null || v.isEmpty ? "Required" : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _agencyZipCtrl,
                      decoration: const InputDecoration(labelText: "ZIP"),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          v == null || v.isEmpty ? "Required" : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  helperText:
                      "≥ 10 characters • 1 uppercase • 1 special character",
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: _validatePassword,
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 8),

              PasswordRules(controller: _passwordCtrl),

              const SizedBox(height: 16),

              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                decoration: InputDecoration(
                  labelText: "Confirm Password",
                  suffixIcon: IconButton(
                    icon: Icon(_showConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                ),
                validator: (v) =>
                    v != _passwordCtrl.text ? "Passwords don’t match" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _codeCtrl,
                decoration:
                    const InputDecoration(labelText: "Agent Registration Code"),
                validator: (v) =>
                    v == null || v.isEmpty
                        ? "Enter agent registration code"
                        : null,
              ),

              const SizedBox(height: 24),

            ],
          ),
        ),
      ),

      bottomNavigationBar: SafeBottomButton(
        label: "Complete Registration",
        icon: Icons.check,
        onPressed: _tryRegister,
        loading: _loading,
        color: Colors.deepPurple,
      ),
    );
  }
}
