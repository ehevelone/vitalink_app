import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/services/data_repository.dart';
import 'package:vitalink/services/device_id.dart';
import 'package:vitalink/services/device_security_service.dart';
import 'package:vitalink/services/secure_store.dart';

String _profilesJson(List<Profile> profiles) =>
    jsonEncode(profiles.map((p) => p.toJson()).toList());

Future<void> _signInUser(String id) async {
  final store = SecureStore();
  await store.clearAuth();
  await store.setString('userId', id);
  await store.setString('userSessionToken', 'session-$id');
}

Future<void> _signInAgent(String id) async {
  final store = SecureStore();
  await store.clearAuth();
  await store.setString('agentId', id);
  await store.setString('agentSessionToken', 'agent-session-$id');
}

void main() {
  // The test binding also makes every HTTP call return 400, so background
  // profile sync never reaches the real server.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('legacy device-wide profiles move into the signed-in client account',
      () async {
    final legacy = [Profile(fullName: 'Pat Client')];
    SharedPreferences.setMockInitialValues({
      'profiles_json': _profilesJson(legacy),
    });
    await _signInUser('42');

    final loaded = await DataRepository().loadAllProfiles();
    expect(loaded.map((p) => p.fullName), ['Pat Client']);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('profiles_json'), isNull,
        reason: 'unencrypted legacy copy must be removed');
    expect(await SecureStore().getString('profiles_json_user_42'), isNotNull);
  });

  test('an agent signing in first does not claim legacy client profiles',
      () async {
    SharedPreferences.setMockInitialValues({
      'profiles_json': _profilesJson([Profile(fullName: 'Pat Client')]),
    });
    await _signInAgent('9');

    final agentProfiles = await DataRepository().loadAllProfiles();
    expect(agentProfiles, isEmpty);

    await _signInUser('42');
    final clientProfiles = await DataRepository().loadAllProfiles();
    expect(clientProfiles.map((p) => p.fullName), ['Pat Client']);
  });

  test('every short legacy profile id migrates to the server-compatible v5 id',
      () async {
    await _signInUser('42');
    await SecureStore().setString(
      'profiles_json_user_42',
      _profilesJson([
        Profile(id: '1712345678901', fullName: 'First'),
        Profile(id: '1712345678902', fullName: 'Second'),
      ]),
    );

    final loaded = await DataRepository().loadAllProfiles();
    expect(loaded.map((p) => p.id), [
      const Uuid().v5(Uuid.NAMESPACE_URL, '1712345678901'),
      const Uuid().v5(Uuid.NAMESPACE_URL, '1712345678902'),
    ]);
  });

  test('switching accounts keeps each account\'s profiles separate and intact',
      () async {
    await _signInUser('1');
    await DataRepository().addProfile(Profile(fullName: 'Account One'));

    await _signInUser('2');
    expect(await DataRepository().loadAllProfiles(), isEmpty);
    await DataRepository().addProfile(Profile(fullName: 'Account Two'));

    await _signInUser('1');
    final first = await DataRepository().loadAllProfiles();
    expect(first.map((p) => p.fullName), ['Account One']);
  });

  test('a disabled phone gets a fresh device id so it can log in again',
      () async {
    await _signInUser('42');
    final revokedId = await DeviceId.getOrCreate();

    await DeviceSecurityService.disableCurrentDevice(reason: 'replaced');

    final nextId = await DeviceId.getOrCreate();
    expect(nextId, isNot(revokedId),
        reason: 'the server keeps the old id revoked forever');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('revokedDeviceId'), revokedId);
  });

  test('erase after a repeated device disable still removes that account',
      () async {
    await _signInUser('42');
    await DataRepository().addProfile(Profile(fullName: 'Pat Client'));

    // Push/startup disable, then a later login attempt disables again after
    // auth was already cleared.
    await DeviceSecurityService.disableCurrentDevice(reason: 'replaced');
    await DeviceSecurityService.disableCurrentDevice(reason: 'replaced');

    expect(await SecureStore().getString('profiles_json_user_42'), isNotNull,
        reason: 'replaced devices keep data until the user erases it');

    await DeviceSecurityService.erasePreservedLocalData();
    expect(await SecureStore().getString('profiles_json_user_42'), isNull);
  });
}
