import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageOption {
  final String code;
  final String label;
  final String nativeLabel;

  const LanguageOption({
    required this.code,
    required this.label,
    required this.nativeLabel,
  });
}

class LanguageService {
  static const _languageKey = 'display_language';

  static const supportedLanguages = [
    LanguageOption(
      code: 'system',
      label: 'Use phone language',
      nativeLabel: 'Use phone language',
    ),
    LanguageOption(
      code: 'en',
      label: 'English',
      nativeLabel: 'English',
    ),
    LanguageOption(
      code: 'es',
      label: 'Spanish',
      nativeLabel: 'Español',
    ),
  ];

  static final ValueNotifier<Locale?> localeNotifier =
      ValueNotifier<Locale?>(null);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_languageKey) ?? 'system';
    localeNotifier.value = _localeFromCode(code);
  }

  static Future<String> getLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? 'system';
  }

  static Future<String> getEffectiveLanguageCode() async {
    final saved = await getLanguageCode();
    if (saved == 'es' || saved == 'en') return saved;

    final platformCode =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return platformCode == 'es' ? 'es' : 'en';
  }

  static Future<void> setLanguageCode(String code) async {
    final normalized = _isSupported(code) ? code : 'system';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, normalized);
    localeNotifier.value = _localeFromCode(normalized);
  }

  static Locale? _localeFromCode(String code) {
    if (code == 'system') return null;
    return Locale(code);
  }

  static bool _isSupported(String code) {
    return supportedLanguages.any((language) => language.code == code);
  }
}
