import 'dart:math';

import 'secure_store.dart';

class DeviceId {
  static const String _key = 'deviceId';

  /// Returns a stable per-install device id stored in SecureStore.
  static Future<String> getOrCreate() async {
    final store = SecureStore();

    final existing = await store.getString(_key);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final fresh = _generate();
    await store.setString(_key, fresh);
    return fresh;
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