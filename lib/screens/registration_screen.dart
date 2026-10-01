import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/app_state.dart';
import '../services/deep_link_service.dart';
import '../services/secure_store.dart';
import '../services/device_id.dart';
import '../widgets/password_rules.dart';
import '../widgets/safe_bottom_button.dart';
import '../utils/phone_formatter.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  @override
  void initState() {
    super.initState();
  }

  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // ✅ NEW ADDRESS FIELDS
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _activationCodeCtrl = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  bool _activationLoaded = false;
  bool _lookupRunning = false;
  bool _argsLoaded = false;
  bool _agentAccountPrefilled = false;
  String _relationshipType = 'client';
  String? _accessCodeType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_argsLoaded) return;
    _argsLoaded = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    String? code;

    if (args is Map && args['code'] != null) {
      code = args['code'].toString().trim().toUpperCase();
    }

    if (args is Map && args['fromAgentAccount'] == true) {
      _agentAccountPrefilled = true;
      _accessCodeType = 'agent';
      _nameCtrl.text = args['name']?.toString() ?? "";
      _emailCtrl.text = args['email']?.toString() ?? "";
      _phoneCtrl.text = args['phone']?.toString() ?? "";

      final password = args['password']?.toString() ?? "";
      _passwordCtrl.text = password;
      _confirmCtrl.text = password;
    }

    code ??= VitaLinkDeepLink.code?.trim().toUpperCase();

    if (code != null && code.isNotEmpty) {
      _activationCodeCtrl.text = code;

      if (VitaLinkDeepLink.code == code) {
        VitaLinkDeepLink.clear();
      }

      if (_agentAccountPrefilled) {
        _activationLoaded = true;
      } else {
        _lookupActivation();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();

    // ✅ dispose new fields
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();

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
      final access = await ApiService.validateAccessCode(code);

      if (!mounted) return;

      if (access['success'] == true) {
        final type = access['type']?.toString();
        var name = '';
        var email = '';
        if (type == 'personal') {
          final details = await ApiService.lookupActivation(code);
          if (details['success'] == true) {
            name = (details['name'] ?? '').toString();
            email = (details['email'] ?? '').toString();
          }
        }
        if (!mounted) return;
        setState(() {
          _accessCodeType = type;
          if (name.isNotEmpty) _nameCtrl.text = name;
          if (email.isNotEmpty) _emailCtrl.text = email;
          _activationLoaded = true;
        });
      }
    } catch (_) {
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

  String _normalizePhone(String input) {
    return PhoneNumberFormatter.normalizedForApi(input);
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
    if (email.isEmpty) return "Email required";

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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final repo = DataRepository();

      final code = _normalizeCode(_activationCodeCtrl.text);
      final email = _normalizeEmail(_emailCtrl.text);

      final agentRes = await ApiService.validateAccessCode(code);

      if (agentRes['success'] != true) {
        throw Exception("Invalid or inactive activation code");
      }
      _accessCodeType = agentRes['type']?.toString();

      final nameParts = _nameCtrl.text.trim().split(" ");
      final firstName = nameParts.first;
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(" ") : "User";

      final registerRes = await ApiService.registerUser(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: _normalizePhone(_phoneCtrl.text),
        password: _passwordCtrl.text.trim(),
        promoCode: code,
        platform: Platform.isIOS ? "ios" : "android",
        deviceId: await DeviceId.getOrCreate(),
        relationshipType:
            _accessCodeType == 'agent' ? _relationshipType : 'personal',
      );

      if (registerRes['success'] != true) {
        throw Exception(registerRes['error'] ?? "Registration failed");
      }

      final user = registerRes['user'];
      if (user == null) {
        throw Exception("Registration returned no user");
      }

      final store = SecureStore();
      await store.setString("userId", user["id"].toString());
      await store.setString("userEmail", user["email"].toString());
      if (_agentAccountPrefilled) {
        await store.setBool("agentUserAccountCreated", true);
      }

      final sessionToken = user["session_token"]?.toString() ?? "";
      if (sessionToken.isNotEmpty) {
        await store.setString("userSessionToken", sessionToken);
      } else {
        await store.remove("userSessionToken");
      }

      final profile = await repo.loadProfile();

      profile.fullName = _nameCtrl.text.trim();
      profile.emergency =
          profile.emergency.copyWith(phone: _phoneCtrl.text.trim());
      profile.userPhone = _phoneCtrl.text.trim();

      // ✅ SAVE ADDRESS DATA
      profile.address = _addressCtrl.text.trim();
      profile.city = _cityCtrl.text.trim();
      profile.state = _stateCtrl.text.trim();
      profile.zip = _zipCtrl.text.trim();

      profile.registered = true;
      profile.updatedAt = DateTime.now();

      await repo.saveProfile(profile);

      await AppState.setLoggedIn(true);
      await AppState.setRole('user');
      await AppState.setEmail(email);

      if (!mounted) return;

      if (_agentAccountPrefilled) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/account_access', (_) => false);
      } else {
        Navigator.pushReplacementNamed(context, '/account_access');
      }
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
              if (_agentAccountPrefilled) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7FC),
                    border: Border.all(color: const Color(0xFF78C7E7)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.person_add_alt_1, color: Color(0xFF1479B8)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "We filled this in from your agent account. Add your personal address, then complete registration.",
                          style: TextStyle(fontSize: 15, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const Text(
                "ENTER YOUR ACTIVATION CODE",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _activationCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: "Activation Code",
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: _pasteCode,
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? "Activation code required"
                    : null,
              ),

              const SizedBox(height: 20),

              if (_accessCodeType != 'personal') ...[
                const Text(
                  'YOUR CONNECTION',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'client',
                      icon: Icon(Icons.verified_user_outlined),
                      label: Text('Current client'),
                    ),
                    ButtonSegment(
                      value: 'prospect',
                      icon: Icon(Icons.person_search_outlined),
                      label: Text('Not a client yet'),
                    ),
                  ],
                  selected: {_relationshipType},
                  onSelectionChanged: (selection) =>
                      setState(() => _relationshipType = selection.first),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This helps VitaLink apply the correct communication permissions. The client/user will confirm this after registration.',
                  style: TextStyle(color: Colors.black54, height: 1.35),
                ),
                const SizedBox(height: 20),
              ],

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
                validator: _validateEmail,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: "Phone"),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
              ),

              const SizedBox(height: 12),

              // ✅ ADDRESS BLOCK
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: "Address Line 1"),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "Address required" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _cityCtrl,
                decoration: const InputDecoration(labelText: "City"),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "City required" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _stateCtrl,
                decoration: const InputDecoration(labelText: "State"),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "State required" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _zipCtrl,
                decoration: const InputDecoration(labelText: "Zip Code"),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "Zip required" : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword
                        ? Icons.visibility
                        : Icons.visibility_off),
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
                    icon: Icon(_showConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off),
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
