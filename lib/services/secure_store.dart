import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // =========================
  // STRING
  // =========================
  Future<void> setString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> getString(String key) async {
    return await _storage.read(key: key);
  }

  // Alias (your app uses this)
  Future<String?> get(String key) async {
    return await _storage.read(key: key);
  }

  // =========================
  // BOOL
  // =========================
  Future<void> setBool(String key, bool value) async {
    await _storage.write(key: key, value: value.toString());
  }

  Future<bool?> getBool(String key) async {
    final value = await _storage.read(key: key);
    if (value == null) return null;
    return value.toLowerCase() == 'true';
  }

  // =========================
  // REMOVE SINGLE
  // =========================
  Future<void> remove(String key) async {
    await _storage.delete(key: key);
  }

  // =========================
  // CLEAR ALL
  // =========================
  Future<void> clear() async {
    await _storage.deleteAll();
  }

  // =========================
  // CLEAR AUTH
  // =========================
  Future<void> clearAuth() async {
    await _storage.delete(key: 'loggedIn');
    await _storage.delete(key: 'userLoggedIn');
    await _storage.delete(key: 'agentLoggedIn');
    await _storage.delete(key: 'role');
    await _storage.delete(key: 'userEmail');
    await _storage.delete(key: 'userId');
    await _storage.delete(key: 'agent_id');
    await _storage.delete(key: 'device_token');
  }
}
