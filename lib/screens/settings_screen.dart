import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/device_transfer_service.dart';
import '../services/language_service.dart';
import '../services/secure_store.dart';
import '../services/fcm_token_service.dart';
import '../widgets/transfer_code_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _languageCode = 'system';
  bool _loading = true;
  bool _transferWorking = false;
  String _version = '';
  String _buildNumber = '';
  final _transferService = DeviceTransferService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait([
      LanguageService.getLanguageCode(),
      PackageInfo.fromPlatform(),
    ]);
    final code = results[0] as String;
    final packageInfo = results[1] as PackageInfo;
    if (!mounted) return;
    setState(() {
      _languageCode = code;
      _version = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;
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

      final token = await FcmTokenService.getToken();
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
                  fontFamily: 'monospace',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
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

    final code = await showTransferCodeDialog(
      context,
      title: strings.haveTransferCode,
      confirmLabel: strings.restoreTransfer,
    );

    if (code == null || code.isEmpty || !mounted) return;

    setState(() => _transferWorking = true);

    try {
      try {
        await _transferService.redeemTransfer(code);
      } on TransferCleanupException {
        // Profiles were imported; only the server cleanup failed.
      }
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
                Text(
                  strings.about,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('VitaLink'),
                  subtitle: SelectableText(
                    '${strings.version} $_version  |  ${strings.build} $_buildNumber',
                  ),
                ),
              ],
            ),
    );
  }
}
