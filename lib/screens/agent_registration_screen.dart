import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
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
    if (pw == null || pw.isEmpty) return AppStrings.of(context).enterAPassword;
    if (pw.length < 10) return AppStrings.of(context).tenCharsMin;
    if (!RegExp(r'[A-Z]').hasMatch(pw)) {
      return AppStrings.of(context).atLeastOneUppercase;
    }
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(pw)) {
      return AppStrings.of(context).passwordSpecial;
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
    if (email.isEmpty) return AppStrings.of(context).enterValidEmail;

    final emailPattern = RegExp(
      r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$",
    );
    if (!emailPattern.hasMatch(email) ||
        email.contains("..") ||
        email.startsWith(".") ||
        email.endsWith(".")) {
      return AppStrings.of(context).enterValidEmail;
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
      return AppStrings.of(context).checkEmailEnding;
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
        final email = _normalizeEmail(_emailCtrl.text);
        final password = _passwordCtrl.text.trim();
        final requiresAgentBilling = data['requiresAgentBilling'] == true;

        if (requiresAgentBilling) {
          if (!mounted) return;
          _showPopup(
            AppStrings.of(context).agentAccessNotActive,
            AppStrings.of(context).agentAccountNotActive,
          );
          return;
        }

        final store = SecureStore();

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

        final activationCode = data['activationCode']?.toString() ?? "";
        if (activationCode.isNotEmpty) {
          await store.setString("agentPromoCode", activationCode);
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
        if (!mounted) return;
        _showPopup(AppStrings.of(context).registrationFailedTitle,
            data['error'] ?? AppStrings.of(context).unknownErrorX);
      }
    } catch (e) {
      if (!mounted) return;
      _showPopup(AppStrings.of(context).error,
          AppStrings.of(context).registrationFailedError('$e'));
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
      appBar: AppBar(title: Text(AppStrings.of(context).agentRegistration)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).fullName),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterYourName
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).email),
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _npnCtrl,
                decoration: const InputDecoration(labelText: "NPN"),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterYourNpn
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).phoneNumber),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterYourPhoneNumber
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _agencyNameCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agencyName),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterAgencyName
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _agencyStreetCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agencyStreetAddress),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterAgencyAddress
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _agencyCityCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agencyCity),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterAgencyCity
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _agencyStateCtrl,
                      decoration: InputDecoration(
                          labelText: AppStrings.of(context).state),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => v == null || v.isEmpty
                          ? AppStrings.of(context).requiredField
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _agencyZipCtrl,
                      decoration: const InputDecoration(labelText: "ZIP"),
                      keyboardType: TextInputType.number,
                      validator: (v) => v == null || v.isEmpty
                          ? AppStrings.of(context).requiredField
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).password,
                  helperText: AppStrings.of(context).passwordRulesHelper,
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
                  labelText: AppStrings.of(context).confirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _showConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                ),
                validator: (v) => v != _passwordCtrl.text
                    ? AppStrings.of(context).passwordsDontMatchCurly
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agentRegistrationCode),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterAgentRegistrationCodeField
                    : null,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeBottomButton(
        label: AppStrings.of(context).completeRegistration,
        icon: Icons.check,
        onPressed: _tryRegister,
        loading: _loading,
        color: Colors.deepPurple,
      ),
    );
  }
}
