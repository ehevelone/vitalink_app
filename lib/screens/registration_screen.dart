import 'dart:io';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
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
  final _manualOnboardingCodeCtrl = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  bool _activationLoaded = false;
  bool _lookupRunning = false;
  bool _argsLoaded = false;
  bool _agentAccountPrefilled = false;
  String _relationshipType = 'client';
  String? _accessCodeType;

  // Assisted onboarding: details an agent entered for this client on the
  // CRM, agent access page or agent report (link: activate?onboard=CODE).
  bool _onboardingLoaded = false;
  String? _onboardingCode;
  Map<String, dynamic>? _onboardingPayload;
  String? _onboardingMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_argsLoaded) return;
    _argsLoaded = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    String? code;
    String? onboardingCode;

    if (args is Map && args['code'] != null) {
      code = args['code'].toString().trim().toUpperCase();
    }

    if (args is Map && args['onboard'] != null) {
      onboardingCode = args['onboard'].toString().trim().toUpperCase();
    }
    onboardingCode ??= VitaLinkDeepLink.onboardingCode?.trim().toUpperCase();

    if (onboardingCode != null && onboardingCode.isNotEmpty) {
      _onboardingCode = onboardingCode;
      if (VitaLinkDeepLink.onboardingCode == onboardingCode) {
        VitaLinkDeepLink.clearOnboardingCode();
      }
      // Runs after this frame so setState and AppStrings are safe to use.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _lookupAssistedOnboarding());
      return;
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

  Future<void> _lookupAssistedOnboarding() async {
    if (_onboardingLoaded || !mounted) return;

    final code = _onboardingCode?.trim().toUpperCase() ?? "";
    if (code.isEmpty) return;

    final strings = AppStrings.of(context);
    setState(() {
      _loading = true;
      _onboardingMessage = null;
    });

    try {
      final res = await ApiService.getAssistedOnboarding(code);

      if (!mounted) return;

      if (res['success'] != true) {
        setState(() {
          _onboardingMessage =
              (res['error'] ?? strings.assistedOnboardingExpired).toString();
        });
        return;
      }

      final payload = Map<String, dynamic>.from(res['payload'] as Map? ?? {});
      final profile =
          Map<String, dynamic>.from(payload['profile'] as Map? ?? {});

      setState(() {
        _onboardingPayload = payload;
        _onboardingLoaded = true;
        _onboardingMessage = strings.assistedOnboardingLoaded;

        _activationCodeCtrl.text = (payload['activationCode'] ?? '').toString();
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
      setState(() => _onboardingMessage = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadManualOnboardingCode() async {
    final code = _manualOnboardingCodeCtrl.text.trim().toUpperCase();

    if (code.isEmpty) {
      setState(() {
        _onboardingMessage = AppStrings.of(context).enterOnboardingCode;
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

  EmergencyInfo? _emergencyFromOnboarding() {
    final payload = _onboardingPayload;
    if (payload == null) return null;

    final emergency =
        Map<String, dynamic>.from(payload['emergency'] as Map? ?? {});
    if (emergency.isEmpty) return null;

    final contacts = (emergency['contacts'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) =>
            EmergencyContact.fromJson(Map<String, dynamic>.from(item)))
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
      dnrPolstOnFile: emergency['dnrPolstOnFile'] == true,
      dnrPolstLocation: (emergency['dnrPolstLocation'] ?? '').toString(),
    );
  }

  String? _onboardingProfileValue(String key) {
    final payload = _onboardingPayload;
    if (payload == null) return null;

    final profile = Map<String, dynamic>.from(payload['profile'] as Map? ?? {});
    final value = profile[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  List<String> _onboardingReviewLines(AppStrings strings) {
    final payload = _onboardingPayload;
    if (payload == null) return [];

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
    if (emergency['dnrPolstOnFile'] == true) {
      lines.add('${strings.dnrPolstOnFile}: ${strings.yes}');
      add(strings.signedFormLocation, emergency['dnrPolstLocation']);
    }
    return lines;
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
    if (email.isEmpty) return AppStrings.of(context).emailRequired;

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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    // Read wording before any await so it is safe to use after them.
    final strings = AppStrings.of(context);
    try {
      final repo = DataRepository();

      final code = _normalizeCode(_activationCodeCtrl.text);
      final email = _normalizeEmail(_emailCtrl.text);

      final agentRes = await ApiService.validateAccessCode(code);

      if (agentRes['success'] != true) {
        throw Exception(strings.invalidActivationCode);
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
        throw Exception(registerRes['error'] ??
            AppStrings.current().registrationFailedShort);
      }

      final user = registerRes['user'];
      if (user == null) {
        throw Exception(AppStrings.current().registrationReturnedNoUser);
      }

      final store = SecureStore();
      await store.setString("userId", user["id"].toString());
      await store.setString("profileOwnerUserId", user["id"].toString());
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

      // Marks the agent's onboarding package as used. The account already
      // exists at this point, so a failure here must not block the client.
      if (_onboardingCode != null && _onboardingCode!.isNotEmpty) {
        try {
          await ApiService.claimAssistedOnboarding(
            code: _onboardingCode!,
            userId: user["id"].toString(),
          );
        } catch (_) {}
      }

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
        SnackBar(
            content: Text(AppStrings.of(context).registrationFailed('$e'))),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _assistedOnboardingPrompt(AppStrings strings) {
    return Container(
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
                onPressed: _loading ? null : _loadManualOnboardingCode,
                child: Text(strings.loadMyInfo),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _assistedOnboardingStatus(AppStrings strings) {
    final reviewLines = _onboardingReviewLines(strings);
    return [
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
      if (reviewLines.isNotEmpty) ...[
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
              ...reviewLines.map(
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).userRegistration)),
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.person_add_alt_1, color: Color(0xFF1479B8)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppStrings.of(context).prefilledFromAgentAccount,
                          style: const TextStyle(fontSize: 15, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (!_agentAccountPrefilled) ...[
                _assistedOnboardingPrompt(AppStrings.of(context)),
                const SizedBox(height: 20),
              ],
              Text(
                AppStrings.of(context).enterActivationCode,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _activationCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).activationCode,
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: _pasteCode,
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppStrings.of(context).activationCodeRequired
                    : null,
              ),

              ..._assistedOnboardingStatus(AppStrings.of(context)),

              const SizedBox(height: 20),

              if (_accessCodeType != 'personal') ...[
                Text(
                  AppStrings.of(context).yourConnectionCaps,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'client',
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(AppStrings.of(context).currentClient),
                    ),
                    ButtonSegment(
                      value: 'prospect',
                      icon: const Icon(Icons.person_search_outlined),
                      label: Text(AppStrings.of(context).notClientYet),
                    ),
                  ],
                  selected: {_relationshipType},
                  onSelectionChanged: (selection) =>
                      setState(() => _relationshipType = selection.first),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.of(context).connectionHelpsPermissions,
                  style: const TextStyle(color: Colors.black54, height: 1.35),
                ),
                const SizedBox(height: 20),
              ],

              TextFormField(
                controller: _nameCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).fullName),
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppStrings.of(context).nameRequired
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
                controller: _phoneCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).phone),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
              ),

              const SizedBox(height: 12),

              // ✅ ADDRESS BLOCK
              TextFormField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).addressLine1),
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppStrings.of(context).addressRequired
                    : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _cityCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).city),
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppStrings.of(context).cityRequired
                    : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _stateCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).state),
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppStrings.of(context).stateRequired
                    : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _zipCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).zipCode),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppStrings.of(context).zipRequired
                    : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).password,
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
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).requiredField
                    : null,
              ),

              const SizedBox(height: 8),
              PasswordRules(controller: _passwordCtrl),

              const SizedBox(height: 12),

              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirmPassword,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).confirmPassword,
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
                validator: (v) => v != _passwordCtrl.text
                    ? AppStrings.of(context).passwordsDontMatch
                    : null,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeBottomButton(
        label: AppStrings.of(context).completeRegistration,
        icon: Icons.check,
        loading: _loading,
        onPressed: _register,
      ),
    );
  }
}
