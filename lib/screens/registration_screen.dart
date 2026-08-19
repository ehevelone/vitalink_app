import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/app_state.dart';
import '../services/deep_link_service.dart';
import '../services/secure_store.dart';
import '../widgets/password_rules.dart';
import '../widgets/safe_bottom_button.dart';
import '../utils/phone_formatter.dart';
import '../l10n/app_strings.dart';
import '../models.dart';

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
  final _manualOnboardingCodeCtrl = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  bool _activationLoaded = false;
  bool _lookupRunning = false;
  bool _argsLoaded = false;
  bool _onboardingLoaded = false;
  String? _onboardingCode;
  Map<String, dynamic>? _onboardingPayload;
  String? _onboardingMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_argsLoaded) return;
    _argsLoaded = true;

    String? code;
    String? onboardingCode;

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map && args['code'] != null) {
      code = args['code'].toString().trim().toUpperCase();
    }

    if (args is Map && args['onboard'] != null) {
      onboardingCode = args['onboard'].toString().trim().toUpperCase();
    }

    code ??= VitaLinkDeepLink.code?.trim().toUpperCase();
    onboardingCode ??= VitaLinkDeepLink.onboardingCode?.trim().toUpperCase();

    if (onboardingCode != null && onboardingCode.isNotEmpty) {
      _onboardingCode = onboardingCode;

      if (VitaLinkDeepLink.onboardingCode == onboardingCode) {
        VitaLinkDeepLink.clearOnboardingCode();
      }

      _lookupAssistedOnboarding();
      return;
    }

    if (code != null && code.isNotEmpty) {
      _activationCodeCtrl.text = code;

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

    // ✅ dispose new fields
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();

    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _activationCodeCtrl.dispose();
    _manualOnboardingCodeCtrl.dispose();
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
    } finally {
      _lookupRunning = false;
    }
  }

  Future<void> _lookupAssistedOnboarding() async {
    if (_onboardingLoaded) return;

    final code = _onboardingCode?.trim().toUpperCase() ?? "";
    if (code.isEmpty) return;

    setState(() {
      _loading = true;
      _onboardingMessage = null;
    });

    try {
      final res = await ApiService.getAssistedOnboarding(code);

      if (!mounted) return;

      if (res['success'] != true) {
        setState(() {
          _onboardingMessage = (res['error'] ??
                  AppStrings.of(context).assistedOnboardingExpired)
              .toString();
        });
        return;
      }

      final payload =
          Map<String, dynamic>.from(res['payload'] as Map? ?? {});
      final profile =
          Map<String, dynamic>.from(payload['profile'] as Map? ?? {});

      setState(() {
        _onboardingPayload = payload;
        _onboardingLoaded = true;
        _onboardingMessage =
            AppStrings.of(context).assistedOnboardingLoaded;

        _activationCodeCtrl.text =
            (payload['activationCode'] ?? '').toString();
        _nameCtrl.text = (profile['fullName'] ?? '').toString();
        _emailCtrl.text = (profile['email'] ?? '').toString();
        _phoneCtrl.text = (profile['userPhone'] ?? '').toString();
        _addressCtrl.text = (profile['address'] ?? '').toString();
        _cityCtrl.text = (profile['city'] ?? '').toString();
        _stateCtrl.text = (profile['state'] ?? '').toString();
        _zipCtrl.text = (profile['zip'] ?? '').toString();
        _activationLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _onboardingMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadManualOnboardingCode() async {
    final code = _manualOnboardingCodeCtrl.text.trim().toUpperCase();
    final strings = AppStrings.of(context);

    if (code.isEmpty) {
      setState(() {
        _onboardingMessage = strings.enterOnboardingCode;
      });
      return;
    }

    setState(() {
      _onboardingCode = code;
      _onboardingLoaded = false;
      _onboardingPayload = null;
      _onboardingMessage = null;
    });

    await _lookupAssistedOnboarding();
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

  EmergencyInfo? _emergencyFromOnboarding() {
    final payload = _onboardingPayload;
    if (payload == null) return null;

    final emergency =
        Map<String, dynamic>.from(payload['emergency'] as Map? ?? {});

    if (emergency.isEmpty) return null;

    final contacts = (emergency['contacts'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => EmergencyContact.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((contact) => contact.hasDetails)
        .toList();

    return EmergencyInfo(
      contact: contacts.isNotEmpty ? contacts.first.name : '',
      phone: contacts.isNotEmpty ? contacts.first.phone : '',
      contacts: contacts,
      allergies: (emergency['allergies'] ?? '').toString(),
      conditions: (emergency['conditions'] ?? '').toString(),
      bloodType: (emergency['bloodType'] ?? '').toString(),
      implants: (emergency['implants'] ?? '').toString(),
      procedures: (emergency['procedures'] ?? '').toString(),
      organDonor: emergency['organDonor'] == true,
    );
  }

  String? _onboardingProfileValue(String key) {
    final payload = _onboardingPayload;
    if (payload == null) return null;

    final profile = Map<String, dynamic>.from(payload['profile'] as Map? ?? {});
    final value = profile[key]?.toString().trim();

    return value == null || value.isEmpty ? null : value;
  }

  List<String> _onboardingReviewLines() {
    final payload = _onboardingPayload;
    if (payload == null) return [];

    final strings = AppStrings.of(context);
    final profile = Map<String, dynamic>.from(payload['profile'] as Map? ?? {});
    final emergency =
        Map<String, dynamic>.from(payload['emergency'] as Map? ?? {});
    final contacts = (emergency['contacts'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final lines = <String>[];

    void add(String label, Object? value) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) lines.add('$label: $text');
    }

    add(strings.dateOfBirth, profile['dob']);

    for (var i = 0; i < contacts.length; i += 1) {
      final contact = contacts[i];
      final details = [
        contact['name']?.toString().trim() ?? '',
        contact['phone']?.toString().trim() ?? '',
      ].where((item) => item.isNotEmpty).join(' - ');

      add(strings.emergencyContactNumber(i + 1), details);
    }

    add(strings.bloodType, emergency['bloodType']);
    add(strings.allergies, emergency['allergies']);
    add(strings.conditions, emergency['conditions']);
    add(strings.implantedDevices, emergency['implants']);
    add(strings.majorProcedures, emergency['procedures']);

    if (emergency['organDonor'] == true) {
      lines.add('${strings.organDonor}: ${strings.yes}');
    }

    return lines;
  }

  String? _validateEmail(String? value) {
    final strings = AppStrings.of(context);
    final email = _normalizeEmail(value ?? "");
    if (email.isEmpty) return strings.emailRequired;

    final emailPattern = RegExp(
      r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$",
    );
    if (!emailPattern.hasMatch(email) ||
        email.contains("..") ||
        email.startsWith(".") ||
        email.endsWith(".")) {
      return strings.enterValidEmail;
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
      return strings.checkEmailEnding;
    }

    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final strings = AppStrings.of(context);

    setState(() => _loading = true);

    try {
      final repo = DataRepository();

      final code = _normalizeCode(_activationCodeCtrl.text);
      final email = _normalizeEmail(_emailCtrl.text);

      final agentRes = await ApiService.resolveAgentByCode(code);

      if (agentRes['success'] != true || agentRes['agent'] == null) {
        throw Exception(strings.invalidActivationCode);
      }

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
      profile.dob = _onboardingProfileValue('dob') ?? profile.dob;

      // ✅ SAVE ADDRESS DATA
      profile.address = _addressCtrl.text.trim();
      profile.city = _cityCtrl.text.trim();
      profile.state = _stateCtrl.text.trim();
      profile.zip = _zipCtrl.text.trim();

      final onboardingEmergency = _emergencyFromOnboarding();
      if (onboardingEmergency != null) {
        profile.emergency = onboardingEmergency;
      }

      profile.registered = true;
      profile.updatedAt = DateTime.now();

      await repo.saveProfile(profile);

      if (_onboardingCode != null && _onboardingCode!.isNotEmpty) {
        await ApiService.claimAssistedOnboarding(
          code: _onboardingCode!,
          userId: user["id"].toString(),
        );
      }

      await AppState.setLoggedIn(true);
      await AppState.setRole('user');
      await AppState.setEmail(email);

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, '/menu');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.registrationFailed('$e'))),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.userRegistration)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.assistedOnboardingPromptTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      strings.assistedOnboardingPromptBody,
                      style: const TextStyle(color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualOnboardingCodeCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: strings.onboardingCode,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed:
                              _loading ? null : _loadManualOnboardingCode,
                          child: Text(strings.loadMyInfo),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                strings.enterActivationCode,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _activationCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: strings.activationCode,
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: _pasteCode,
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? strings.activationCodeRequired
                    : null,
              ),

              if (_onboardingMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _onboardingMessage!,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              if (_onboardingReviewLines().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.reviewAgentEnteredDetails,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._onboardingReviewLines().map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            line,
                            style: const TextStyle(color: Color(0xFF334155)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: strings.fullName),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? strings.nameRequired : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(labelText: strings.email),
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                decoration: InputDecoration(labelText: strings.phone),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
              ),

              const SizedBox(height: 12),

              // ✅ ADDRESS BLOCK
              TextFormField(
                controller: _addressCtrl,
                decoration: InputDecoration(labelText: strings.addressLine1),
                validator: (v) => v == null || v.trim().isEmpty
                    ? strings.addressRequired
                    : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _cityCtrl,
                decoration: InputDecoration(labelText: strings.city),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? strings.cityRequired : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _stateCtrl,
                decoration: InputDecoration(labelText: strings.state),
                validator: (v) => v == null || v.trim().isEmpty
                    ? strings.stateRequired
                    : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _zipCtrl,
                decoration: InputDecoration(labelText: strings.zipCode),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? strings.zipRequired : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: strings.password,
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
                validator: (v) =>
                    v == null || v.isEmpty ? strings.requiredField : null,
              ),

              const SizedBox(height: 8),
              PasswordRules(controller: _passwordCtrl),

              const SizedBox(height: 12),

              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirmPassword,
                decoration: InputDecoration(
                  labelText: strings.confirmPassword,
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
                    v != _passwordCtrl.text ? strings.passwordsDontMatch : null,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeBottomButton(
        label: strings.completeRegistration,
        icon: Icons.check,
        loading: _loading,
        onPressed: _register,
      ),
    );
  }
}
