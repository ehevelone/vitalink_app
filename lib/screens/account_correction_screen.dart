import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/screen_strings.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

/// Server calls used by [AccountCorrectionScreen]; replaceable in tests.
abstract class AccountCorrectionApi {
  Future<Map<String, dynamic>> start({
    required String userId,
    required String currentEmail,
    required String password,
    String? newName,
    String? newEmail,
  });

  Future<Map<String, dynamic>> confirm({
    required String userId,
    required String correctionId,
    required String code,
    String? newEmailCode,
  });
}

class _ServerAccountCorrectionApi implements AccountCorrectionApi {
  const _ServerAccountCorrectionApi();

  @override
  Future<Map<String, dynamic>> start({
    required String userId,
    required String currentEmail,
    required String password,
    String? newName,
    String? newEmail,
  }) =>
      ApiService.startAccountCorrection(
        userId: userId,
        currentEmail: currentEmail,
        password: password,
        newName: newName,
        newEmail: newEmail,
      );

  @override
  Future<Map<String, dynamic>> confirm({
    required String userId,
    required String correctionId,
    required String code,
    String? newEmailCode,
  }) =>
      ApiService.confirmAccountCorrection(
        userId: userId,
        correctionId: correctionId,
        code: code,
        newEmailCode: newEmailCode,
      );
}

/// "Fix my name or email". The account name and email are locked after
/// registration; changing them needs the current email and password, then the
/// code emailed to the address on file (and one sent to a new address).
/// Returns true when the account was changed.
class AccountCorrectionScreen extends StatefulWidget {
  const AccountCorrectionScreen({
    super.key,
    required this.currentName,
    required this.currentEmail,
    this.api = const _ServerAccountCorrectionApi(),
    this.onCorrected,
  });

  final String currentName;
  final String currentEmail;
  final AccountCorrectionApi api;

  /// Saves the confirmed name/email on this phone. Defaults to
  /// [saveCorrectedAccountLocally]; replaceable in tests.
  final Future<void> Function(String name, String email)? onCorrected;

  @override
  State<AccountCorrectionScreen> createState() =>
      _AccountCorrectionScreenState();
}

/// Updates this phone's saved login and the account holder's profile, only
/// after the server confirmed the change.
Future<void> saveCorrectedAccountLocally(String name, String email) async {
  final store = SecureStore();
  if (name.isNotEmpty) {
    await store.setString('profileName', name);
    await DataRepository().updateAccountHolderName(name);
  }
  if (email.isNotEmpty) {
    await store.setString('userEmail', email);
    await AppState.setEmail(email);
    if (await store.getBool('rememberMeUser') == true) {
      await store.setString('savedUserEmail', email);
    }
  }
}

class _AccountCorrectionScreenState extends State<AccountCorrectionScreen> {
  final _detailsKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _newEmailCtrl;
  final _currentEmailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newEmailCodeCtrl = TextEditingController();

  bool _working = false;
  String? _error;
  String? _correctionId;
  bool _needsNewEmailCode = false;
  String _sentTo = '';
  String _newEmailSentTo = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.currentName);
    _newEmailCtrl = TextEditingController(text: widget.currentEmail);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _newEmailCtrl.dispose();
    _currentEmailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _newEmailCodeCtrl.dispose();
    super.dispose();
  }

  String _messageFor(Map<String, dynamic> res) {
    final strings = AppStrings.of(context);
    switch (res['code']) {
      case 'credentials_mismatch':
        return strings.correctionCredentialsMismatch;
      case 'too_many_attempts':
        return strings.correctionTooManyAttempts;
      case 'code_incorrect':
        return strings.correctionCodeIncorrect;
      case 'code_expired':
        return strings.correctionCodeExpired;
      case 'email_unavailable':
      case 'email_in_use':
        return strings.correctionEmailInUse;
      case 'nothing_to_change':
        return strings.correctionNothingToChange;
      default:
        return strings.correctionFailed;
    }
  }

  Future<String> _userId() async =>
      (await SecureStore().getString('userId') ?? '').trim();

  Future<void> _sendCode() async {
    if (!_detailsKey.currentState!.validate()) return;
    final newName = _nameCtrl.text.trim();
    final newEmail = _newEmailCtrl.text.trim();
    if (newName == widget.currentName.trim() &&
        newEmail.toLowerCase() == widget.currentEmail.trim().toLowerCase()) {
      setState(() =>
          _error = AppStrings.of(context).correctionNothingToChange);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final res = await widget.api.start(
        userId: await _userId(),
        currentEmail: _currentEmailCtrl.text.trim(),
        password: _passwordCtrl.text,
        newName: newName == widget.currentName.trim() ? null : newName,
        newEmail: newEmail.toLowerCase() ==
                widget.currentEmail.trim().toLowerCase()
            ? null
            : newEmail,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _correctionId = res['correctionId']?.toString();
          _needsNewEmailCode = res['needsNewEmailCode'] == true;
          _sentTo = res['sentTo']?.toString() ?? '';
          _newEmailSentTo = res['newEmailSentTo']?.toString() ?? '';
          // The password is not needed again; do not keep it in memory.
          _passwordCtrl.clear();
        });
      } else {
        setState(() => _error = _messageFor(res));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.of(context).correctionFailed);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirm() async {
    final code = _codeCtrl.text.trim();
    final newEmailCode = _newEmailCodeCtrl.text.trim();
    if (code.isEmpty || (_needsNewEmailCode && newEmailCode.isEmpty)) {
      setState(() => _error = AppStrings.of(context).requiredField);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final res = await widget.api.confirm(
        userId: await _userId(),
        correctionId: _correctionId!,
        code: code,
        newEmailCode: _needsNewEmailCode ? newEmailCode : null,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        await (widget.onCorrected ?? saveCorrectedAccountLocally)(
          res['name']?.toString().trim() ?? '',
          res['email']?.toString().trim() ?? '',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).accountCorrected)),
        );
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _error = _messageFor(res);
        if (res['code'] == 'code_expired') {
          // Start over from the details step.
          _correctionId = null;
          _codeCtrl.clear();
          _newEmailCodeCtrl.clear();
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.of(context).correctionFailed);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String? _required(String? value) => (value ?? '').trim().isEmpty
      ? AppStrings.of(context).requiredField
      : null;

  Widget _bigButton(String label, VoidCallback? onPressed, {Key? key}) =>
      FilledButton(
        key: key,
        onPressed: _working ? null : onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        child: _working
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label, style: const TextStyle(fontSize: 18)),
      );

  Widget _detailsStep(AppStrings strings) => Form(
        key: _detailsKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.fixNameOrEmailIntro,
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('correction-name'),
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: strings.correctName),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('correction-new-email'),
              controller: _newEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: strings.correctEmail),
              validator: _required,
            ),
            const Divider(height: 36),
            TextFormField(
              key: const Key('correction-current-email'),
              controller: _currentEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration:
                  InputDecoration(labelText: strings.currentEmailLabel),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('correction-password'),
              controller: _passwordCtrl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration:
                  InputDecoration(labelText: strings.currentPasswordLabel),
              validator: _required,
            ),
            const SizedBox(height: 24),
            _bigButton(strings.sendCode, _sendCode,
                key: const Key('correction-send-code')),
          ],
        ),
      );

  Widget _codeStep(AppStrings strings) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.codeSentTo(_sentTo),
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('correction-code'),
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(fontSize: 22, letterSpacing: 4),
            decoration: InputDecoration(labelText: strings.verificationCode),
          ),
          if (_needsNewEmailCode) ...[
            const SizedBox(height: 8),
            Text(strings.newEmailCodeSentTo(_newEmailSentTo),
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            TextField(
              key: const Key('correction-new-email-code'),
              controller: _newEmailCodeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(fontSize: 22, letterSpacing: 4),
              decoration: InputDecoration(labelText: strings.newEmailCode),
            ),
          ],
          const SizedBox(height: 16),
          _bigButton(strings.confirmChange, _confirm,
              key: const Key('correction-confirm')),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.fixNameOrEmail)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null) ...[
              Container(
                key: const Key('correction-error'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade900, fontSize: 16),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _correctionId == null ? _detailsStep(strings) : _codeStep(strings),
          ],
        ),
      ),
    );
  }
}
