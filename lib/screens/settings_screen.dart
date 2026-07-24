import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadLanguage();
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
              ],
            ),
    );
  }
}
