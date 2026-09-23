import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/device_transfer_service.dart';
import '../services/language_service.dart';
import '../services/secure_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _languageCode = 'system';
  bool _loading = true;
  bool _transferWorking = false;
  bool _revocationWorking = false;
  String? _authorizationAgent;
  String? _revokedAt;
  String? _agentNotifiedAt;
  String? _authorizationError;
  final _transferService = DeviceTransferService();

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _loadAuthorizationStatus();
  }

  Future<void> _loadAuthorizationStatus() async {
    final userId = await SecureStore().getString('userId');
    if (userId == null || userId.isEmpty) return;
    final result = await ApiService.getAuthorizationStatus(userId: userId);
    if (!mounted) return;
    setState(() {
      if (result['success'] == true) {
        _authorizationAgent = result['agentName']?.toString();
        _revokedAt = result['revokedAt']?.toString();
        _agentNotifiedAt = result['agentNotifiedAt']?.toString();
        _authorizationError = null;
      } else {
        _authorizationError = result['error']?.toString() ?? 'Unable to load permission status.';
      }
    });
  }

  Future<void> _sendRevocation() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.revocationConfirmTitle),
        content: Text(_revokedAt != null
            ? strings.agentNoticePending
            : strings.revocationConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_revokedAt != null
                ? strings.retryAgentNotice
                : strings.sendRevocation),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final userId = await SecureStore().getString('userId');
    if (userId == null || userId.isEmpty) return;
    setState(() => _revocationWorking = true);
    try {
      final result = await ApiService.sendAuthorizationRevocation(userId: userId);
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _revokedAt = result['revokedAt']?.toString();
          _agentNotifiedAt = DateTime.now().toIso8601String();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.revocationSent)),
        );
      } else {
        if (result['recorded'] == true) {
          await _loadAuthorizationStatus();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['recorded'] == true
              ? strings.agentNoticePending
              : result['error']?.toString() ?? 'Unable to send revocation.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _revocationWorking = false);
    }
  }

  Future<void> _loadLanguage() async {
    final code = await LanguageService.getLanguageCode();
    if (!mounted) return;
    setState(() {
      _languageCode = code;
      _loading = false;
    });
  }

  Future<void> _setLanguage(String? code) async {
    if (code == null) return;
    await LanguageService.setLanguageCode(code);
    await _refreshDeviceLanguage();
    if (!mounted) return;
    setState(() => _languageCode = code);
    final strings = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.languageSaved)),
    );
  }

  Future<void> _refreshDeviceLanguage() async {
    try {
      final store = SecureStore();
      final userId = await store.getString("userId");
      if (userId == null || userId.isEmpty) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await ApiService.registerDeviceToken(
        userId: userId,
        fcmToken: token,
      );
    } catch (_) {}
  }

  String _languageLabel(LanguageOption language, AppStrings strings) {
    switch (language.code) {
      case 'system':
        return strings.usePhoneLanguage;
      case 'en':
        return strings.english;
      case 'es':
        return '${language.nativeLabel} (${strings.spanish})';
      default:
        return language.label;
    }
  }

  Future<void> _createTransfer() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.moveToNewDevice),
        content: Text(strings.transferWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.createTransferCode),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _transferWorking = true);

    try {
      final result = await _transferService.createTransfer();
      if (!mounted) return;

      final code = result['transferCode']?.toString() ?? '';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.transferCodeCreated),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(strings.transferCodeExpires),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(strings.copied)),
                );
              },
              child: Text(strings.copyCode),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(strings.ok),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _transferWorking = false);
    }
  }

  Future<void> _redeemTransfer() async {
    final strings = AppStrings.of(context);
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.haveTransferCode),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: strings.enterTransferCode),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(strings.restoreTransfer),
          ),
        ],
      ),
    );

    controller.dispose();

    if (code == null || code.isEmpty || !mounted) return;

    setState(() => _transferWorking = true);

    try {
      await _transferService.redeemTransfer(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.transferComplete)),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/menu', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _transferWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  strings.language,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.chooseDisplayLanguage,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _languageCode,
                  decoration: InputDecoration(
                    labelText: strings.displayLanguage,
                  ),
                  items: LanguageService.supportedLanguages
                      .map(
                        (language) => DropdownMenuItem<String>(
                          value: language.code,
                          child: Text(_languageLabel(language, strings)),
                        ),
                      )
                      .toList(),
                  onChanged: _setLanguage,
                ),
                const SizedBox(height: 28),
                Text(
                  strings.moveToNewDevice,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.moveToNewDeviceBody,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.transferWarning,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _transferWorking ? null : _createTransfer,
                  child: Text(
                    _transferWorking
                        ? strings.creatingTransfer
                        : strings.createTransferCode,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _transferWorking ? null : _redeemTransfer,
                  child: Text(strings.haveTransferCode),
                ),
                const SizedBox(height: 28),
                Text(strings.authorizationsTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(strings.authorizationsBody,
                    style: const TextStyle(color: Colors.black54)),
                if (_authorizationAgent != null) ...[
                  const SizedBox(height: 8),
                  Text('${strings.myAgent}: $_authorizationAgent'),
                ],
                if (_authorizationError != null) ...[
                  const SizedBox(height: 8),
                  Text(_authorizationError!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                if (_revokedAt != null && _agentNotifiedAt != null)
                  Text(strings.revocationAlreadySent)
                else
                  OutlinedButton(
                    onPressed: _revocationWorking
                        ? null
                        : _sendRevocation,
                    child: Text(_revokedAt != null
                        ? strings.retryAgentNotice
                        : strings.sendRevocation),
                  ),
              ],
            ),
    );
  }
}
