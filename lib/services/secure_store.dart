import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
  );

  final FlutterSecureStorage _storage =
      const FlutterSecureStorage(iOptions: _iosOptions);

  // =========================
  // STRING
  // =========================
  Future<void> setString(String key, String value) async {
    await _storage.write(key: key, value: value, iOptions: _iosOptions);
  }

  Future<String?> getString(String key) async {
    return await _storage.read(key: key, iOptions: _iosOptions);
  }

  // Alias
  Future<String?> get(String key) async {
    return await _storage.read(key: key, iOptions: _iosOptions);
  }

  // =========================
  // BOOL
  // =========================
  Future<void> setBool(String key, bool value) async {
    await _storage.write(
        key: key, value: value.toString(), iOptions: _iosOptions);
  }

  Future<bool?> getBool(String key) async {
    final value =
        await _storage.read(key: key, iOptions: _iosOptions);
    if (value == null) return null;
    return value.toLowerCase() == 'true';
  }

  // =========================
  // REMOVE SINGLE
  // =========================
  Future<void> remove(String key) async {
    await _storage.delete(key: key, iOptions: _iosOptions);
  }

  // =========================
  // CLEAR ALL
  // =========================
  Future<void> clear() async {
    await _storage.deleteAll(iOptions: _iosOptions);
  }

  // =========================
  // CLEAR AUTH
  // =========================
  Future<void> clearAuth() async {
    await remove('loggedIn');
    await remove('userLoggedIn');
    await remove('agentLoggedIn');
    await remove('role');
    await remove('userEmail');
    await remove('userId');
    await remove('agent_id');
    await remove('device_token');
  }
}