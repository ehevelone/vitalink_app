import 'dart:io';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';

import '../legal/user_agreement_text.dart';
import '../services/api_service.dart';
import '../services/device_id.dart';
import '../services/secure_store.dart';

class AccountAccessScreen extends StatefulWidget {
  const AccountAccessScreen({super.key});

  @override
  State<AccountAccessScreen> createState() => _AccountAccessScreenState();
}

class _AccountAccessScreenState extends State<AccountAccessScreen> {
  final _codeCtrl = TextEditingController();
  Map<String, dynamic>? _access;
  bool _loading = true;
  bool _working = false;
  bool _userAttestation = false;
  bool _agreementAccepted = false;
  bool _messagingConsent = false;
  bool _prospectMedicareConsent = false;
  bool _prospectLifeConsent = false;
  String _relationship = 'client';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<String?> _userId() => SecureStore().getString('userId');

  Future<void> _load() async {
    final userId = await _userId();
    if (userId == null) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
      return;
    }
    final result = await ApiService.getAccountAccess(userId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _access = Map<String, dynamic>.from(result['access'] as Map? ?? {});
        _agreementAccepted = _access?['agreementCurrent'] == true;
        _messagingConsent = _access?['canMessage'] == true;
        if (_access?['relationshipStatus'] == 'confirmed_prospect' ||
            _access?['relationshipStatus'] == 'pending_prospect_confirmation') {
          _relationship = 'prospect';
        }
        final prospectConsents = Map<String, dynamic>.from(
          _access?['prospectConsents'] as Map? ?? {},
        );
        _prospectMedicareConsent =
            (prospectConsents['medicare'] as Map?)?['status'] == 'granted';
        _prospectLifeConsent =
            (prospectConsents['life'] as Map?)?['status'] == 'granted';
      } else {
        _error = result['error']?.toString() ??
            AppStrings.of(context).unableToCheckAccess;
      }
    });
  }

  Future<Map<String, dynamic>> _auditValues() async => {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'deviceId': await DeviceId.getOrCreate(),
      };

  Future<void> _confirm() async {
    if (!_userAttestation || !_agreementAccepted) {
      setState(() => _error = AppStrings.of(context).clientMustCheckBoth);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final userId = await _userId();
    final result = await ApiService.updateAccountAccess(
      userId: userId!,
      action: 'confirm',
      values: {
        ...await _auditValues(),
        'userAttestation': true,
        'agreementAccepted': true,
        'relationship': _relationship,
        'messagingConsent': _relationship == 'client' && _messagingConsent,
        'prospectConsents': {
          'medicare': _relationship == 'prospect' && _prospectMedicareConsent,
          'life': _relationship == 'prospect' && _prospectLifeConsent,
        },
      },
    );
    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/menu', (_) => false);
    } else {
      setState(() {
        _working = false;
        _error = result['error']?.toString();
      });
    }
  }

  Future<void> _reportWrongAgent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(context).thisDoesntLookRight),
        content: Text(
          AppStrings.of(context).pauseConnectionBody,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.of(context).goBack)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppStrings.of(context).pauseConnection)),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _working = true);
    final userId = await _userId();
    final result = await ApiService.updateAccountAccess(
      userId: userId!,
      action: 'review_requested',
      values: await _auditValues(),
    );
    if (!mounted) return;
    setState(() => _working = false);
    if (result['success'] == true) await _load();
  }

  Future<void> _connectCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final userId = await _userId();
    final result = await ApiService.updateAccountAccess(
      userId: userId!,
      action: 'connect_code',
      values: {'code': code, ...await _auditValues()},
    );
    if (!mounted) return;
    if (result['success'] == true) {
      await _load();
      setState(() => _working = false);
    } else {
      setState(() {
        _working = false;
        _error = result['error']?.toString();
      });
    }
  }

  Future<void> _recoverPersonalCode() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(context).recoverPersonalCode),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration:
              InputDecoration(labelText: AppStrings.of(context).emailAddress),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.of(context).cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(AppStrings.of(context).sendEmail)),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    await ApiService.recoverPersonalAccessCode(email);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(context).checkYourEmail),
        content: Text(AppStrings.of(context).matchingAccountEmailSent),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
        ],
      ),
    );
  }

  Future<void> _showUserAgreement() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(context).vitalinkUserAgreement),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Text(
              userAgreementTextFor(AppStrings.of(context).languageCode),
              style: const TextStyle(height: 1.4),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.of(context).done),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final access = _access ?? const <String, dynamic>{};
    final hasAccess = access['hasAccess'] == true;
    final sponsor = access['sponsor']?.toString();
    final agentName = (access['agentName'] ??
            access['agencyName'] ??
            AppStrings.of(context).thisAgent)
        .toString();
    final prospectOptions = Map<String, dynamic>.from(
      access['prospectOptions'] as Map? ?? {},
    );
    String prospectText(String category, String fallback) {
      final option = prospectOptions[category];
      return option is Map && option['text'] != null
          ? option['text'].toString()
          : fallback;
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: Text(AppStrings.of(context).vitalinkAccess)),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            if (!hasAccess ||
                access['relationshipStatus'] == 'review_requested') ...[
              const Icon(Icons.lock_outline, size: 58, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                AppStrings.of(context).vitalinkAccessRequired,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                AppStrings.of(context).enterValidAccessCode,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agentOrPersonalCode),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _working ? null : _connectCode,
                child: Text(_working
                    ? AppStrings.of(context).checking
                    : AppStrings.of(context).verifyCode),
              ),
              const SizedBox(height: 18),
              Text(
                AppStrings.of(context).personalCodesByEmail,
                style: const TextStyle(color: Colors.black54, height: 1.35),
              ),
              TextButton(
                onPressed: _recoverPersonalCode,
                child: Text(AppStrings.of(context).recoverCodeReceived),
              ),
            ] else ...[
              if (sponsor == 'agent') ...[
                Text(
                  AppStrings.of(context).handDeviceToClient,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.of(context).choicesByClientOnly,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 22),
                Text(
                  AppStrings.of(context).isAgentYourCurrent(agentName),
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'client',
                        label: Text(AppStrings.of(context).currentClient)),
                    ButtonSegment(
                        value: 'prospect',
                        label: Text(AppStrings.of(context).notClientYet)),
                  ],
                  selected: {_relationship},
                  onSelectionChanged: (value) => setState(() {
                    _relationship = value.first;
                    if (_relationship == 'prospect') {
                      _messagingConsent = false;
                    } else {
                      _prospectMedicareConsent = false;
                      _prospectLifeConsent = false;
                    }
                  }),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _working ? null : _reportWrongAgent,
                    child: Text(AppStrings.of(context).thisDoesntLookRight),
                  ),
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _userAttestation,
                onChanged: (value) =>
                    setState(() => _userAttestation = value ?? false),
                title: Text(AppStrings.of(context).iAmTheClient),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agreementAccepted,
                onChanged: access['agreementCurrent'] == true
                    ? null
                    : (value) =>
                        setState(() => _agreementAccepted = value ?? false),
                title: Text(AppStrings.of(context).agreeUserAgreement),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showUserAgreement,
                  icon: const Icon(Icons.description_outlined),
                  label: Text(AppStrings.of(context).reviewUserAgreement),
                ),
              ),
              if (sponsor == 'agent' && _relationship == 'client')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _messagingConsent,
                  onChanged: (value) =>
                      setState(() => _messagingConsent = value ?? false),
                  title: Text(
                    AppStrings.of(context).agentMessagingConsent(agentName),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              if (sponsor == 'agent' && _relationship == 'prospect') ...[
                const SizedBox(height: 8),
                Text(
                  AppStrings.of(context).optionalMessagesFrom(agentName),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.of(context).chooseEitherBothNeither,
                  style: const TextStyle(color: Colors.black54, height: 1.35),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _prospectMedicareConsent,
                  onChanged: (value) => setState(
                    () => _prospectMedicareConsent = value ?? false,
                  ),
                  title: Text(AppStrings.of(context).medicareMessages),
                  subtitle: Text(
                    prospectText(
                        'medicare',
                        AppStrings.of(context)
                            .agreeMedicareMessagesFrom(agentName)),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _prospectLifeConsent,
                  onChanged: (value) => setState(
                    () => _prospectLifeConsent = value ?? false,
                  ),
                  title: Text(AppStrings.of(context).lifeInsuranceMessages),
                  subtitle: Text(
                    prospectText(
                        'life',
                        AppStrings.of(context)
                            .agreeLifeMessagesFrom(agentName)),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _working ? null : _confirm,
                child: Text(_working
                    ? AppStrings.of(context).saving
                    : AppStrings.of(context).confirmAndContinue),
              ),
            ],
            if (_error != null &&
                (!hasAccess ||
                    access['relationshipStatus'] == 'review_requested'))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
