import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';

class DeviceId {
  static const String _key = 'deviceId';
  static const String _fallbackKey = 'vitalinkInstallationId';

  /// Returns a stable per-install device id stored in SecureStore.
  static Future<String> getOrCreate() async {
    final store = SecureStore();
    final prefs = await SharedPreferences.getInstance();

    final existing = await store.getString(_key);
    if (existing != null && existing.trim().isNotEmpty) {
      await prefs.setString(_fallbackKey, existing);
      return existing;
    }

    final fallback = prefs.getString(_fallbackKey);
    if (fallback != null && fallback.trim().isNotEmpty) {
      await store.setString(_key, fallback);
      return fallback;
    }

    final fresh = _generate();
    await store.setString(_key, fresh);
    await prefs.setString(_fallbackKey, fresh);
    return fresh;
  }

  /// Forgets this install's id so the next [getOrCreate] makes a new one.
  /// Used when the server disables this phone: the old id stays revoked on
  /// the server forever, and on iPhone the keychain keeps it even across a
  /// reinstall, so without a fresh id the phone could never log in again.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await SecureStore().remove(_key);
    await prefs.remove(_fallbackKey);
  }

  // 32-hex chars (128-bit) from a cryptographically secure RNG.
  static String _generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
