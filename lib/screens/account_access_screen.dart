import 'dart:io';

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
        _error =
            result['error']?.toString() ?? 'Unable to check account access.';
      }
    });
  }

  Future<Map<String, dynamic>> _auditValues() async => {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'deviceId': await DeviceId.getOrCreate(),
      };

  Future<void> _confirm() async {
    if (!_userAttestation || !_agreementAccepted) {
      setState(
          () => _error = 'The client/user must check both required boxes.');
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
          'medicare':
              _relationship == 'prospect' && _prospectMedicareConsent,
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
        title: const Text("This doesn't look right"),
        content: const Text(
          'This will pause agent messages and future information sharing. It will not delete your account or your information. You can enter the correct agent code afterward.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go Back')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pause Connection')),
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
        title: const Text('Recover personal access code'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email address'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Send Email')),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty || !mounted) return;
    await ApiService.recoverPersonalAccessCode(email);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check your email'),
        content: const Text(
            'If a matching account was found, an email has been sent.'),
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
        title: const Text('VitaLink User Agreement'),
        content: const SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Text(
              userAgreementText,
              style: TextStyle(height: 1.4),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
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
    final agentName =
        (access['agentName'] ?? access['agencyName'] ?? 'this agent')
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
        appBar: AppBar(title: const Text('VitaLink Access')),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            if (!hasAccess ||
                access['relationshipStatus'] == 'review_requested') ...[
              const Icon(Icons.lock_outline, size: 58, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'VitaLink access required',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter a valid agent code or personal access code to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Agent or personal access code'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _working ? null : _connectCode,
                child: Text(_working ? 'Checking...' : 'Verify Code'),
              ),
              const SizedBox(height: 18),
              const Text(
                'Personal access codes are delivered by email after they are issued. Check your inbox and spam folder, then enter your code above.',
                style: TextStyle(color: Colors.black54, height: 1.35),
              ),
              TextButton(
                onPressed: _recoverPersonalCode,
                child: const Text('Recover a code I already received'),
              ),
            ] else ...[
              if (sponsor == 'agent') ...[
                const Text(
                  'Please hand the device to the client/user',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'All confirmations and consent choices below must be completed by the client/user, never by the agent.',
                  style: TextStyle(fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 22),
                Text(
                  'Is $agentName your current insurance agent?',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'client', label: Text('Current client')),
                    ButtonSegment(
                        value: 'prospect', label: Text('Not a client yet')),
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
                    child: const Text("This doesn't look right"),
                  ),
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _userAttestation,
                onChanged: (value) =>
                    setState(() => _userAttestation = value ?? false),
                title: const Text(
                    'I am the client/user and I am making these choices myself.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agreementAccepted,
                onChanged: access['agreementCurrent'] == true
                    ? null
                    : (value) =>
                        setState(() => _agreementAccepted = value ?? false),
                title: const Text(
                    'I have reviewed and agree to the VitaLink User Agreement and Privacy Policy.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showUserAgreement,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Review User Agreement and Privacy Notice'),
                ),
              ),
              if (sponsor == 'agent' && _relationship == 'client')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _messagingConsent,
                  onChanged: (value) =>
                      setState(() => _messagingConsent = value ?? false),
                  title: Text(
                    'I agree to receive in-app and push messages from $agentName, a licensed insurance agent, including coverage reminders and enrollment-period outreach. I understand the agent may be compensated if I enroll in a plan. This consent is optional and may be withdrawn. Leave this unchecked to decide later.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              if (sponsor == 'agent' && _relationship == 'prospect') ...[
                const SizedBox(height: 8),
                Text(
                  'Optional messages from $agentName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose either, both, or neither. These choices do not make you a client and may be changed later.',
                  style: TextStyle(color: Colors.black54, height: 1.35),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _prospectMedicareConsent,
                  onChanged: (value) => setState(
                    () => _prospectMedicareConsent = value ?? false,
                  ),
                  title: const Text('Medicare messages'),
                  subtitle: Text(
                    prospectText('medicare',
                        'I agree to receive optional in-app and push Medicare messages from $agentName.'),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _prospectLifeConsent,
                  onChanged: (value) => setState(
                    () => _prospectLifeConsent = value ?? false,
                  ),
                  title: const Text('Life insurance messages'),
                  subtitle: Text(
                    prospectText('life',
                        'I agree to receive optional in-app and push life insurance messages from $agentName.'),
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
                child: Text(_working ? 'Saving...' : 'Confirm and Continue'),
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
