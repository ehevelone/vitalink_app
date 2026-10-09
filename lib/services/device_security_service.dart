import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_state.dart';
import 'data_repository.dart';
import 'device_id.dart';
import 'secure_store.dart';

class DeviceSecurityService {
  static Future<bool> checkCurrentDevice() async {
    final store = SecureStore();
    final userId = await store.getString('userId');
    if (userId == null || userId.isEmpty) return true;

    final deviceId = await DeviceId.getOrCreate();
    final result = await ApiService.checkDeviceStatus(
      userId: userId,
      deviceId: deviceId,
    );

    if (result['success'] == true && result['active'] == false) {
      await disableCurrentDevice(
        reason: result['reason']?.toString() ?? result['status']?.toString(),
      );
      return false;
    }
    return true;
  }

  static Future<void> disableCurrentDevice({String? reason}) async {
    final deviceId = await DeviceId.getOrCreate();
    final normalizedReason = reason?.trim().toLowerCase() ?? 'unknown';
    final eraseData =
        normalizedReason == 'lost' || normalizedReason == 'stolen';
    final repository = DataRepository();
    final prefs = await SharedPreferences.getInstance();

    // This can run more than once (push, startup check, then a login attempt
    // that returns DEVICE_REVOKED). After the first run auth is cleared and the
    // current suffix is 'unassigned', so keep the account recorded first.
    final currentSuffix = await repository.currentStorageSuffix();
    final recordedSuffix = prefs.getString('revokedProfileStorageSuffix');
    final storageSuffix = currentSuffix != 'unassigned'
        ? currentSuffix
        : (recordedSuffix != null && recordedSuffix.isNotEmpty
            ? recordedSuffix
            : currentSuffix);
    if (storageSuffix != 'unassigned') {
      await prefs.setString('revokedProfileStorageSuffix', storageSuffix);
    }

    if (eraseData) {
      await repository.clearLocalProfiles(storageSuffix: storageSuffix);
    }
    await SecureStore().clearAuth();
    await AppState.clearAuth();

    final alreadyErased = prefs.getBool('revokedDeviceDataErased') ?? false;
    await prefs.setBool('deviceRevoked', true);
    await prefs.setString('revokedDeviceId', deviceId);
    await prefs.setString('deviceRevocationReason', normalizedReason);
    await prefs.setBool('revokedDeviceDataErased', eraseData || alreadyErased);

    // The server keeps this id revoked. A fresh id lets the next login reach
    // the normal "New App Installation Detected" choices instead of being
    // sent straight back to this screen.
    await DeviceId.reset();
  }

  static Future<void> erasePreservedLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final storageSuffix = prefs.getString('revokedProfileStorageSuffix');
    await DataRepository().clearLocalProfiles(storageSuffix: storageSuffix);
    await prefs.setBool('revokedDeviceDataErased', true);
  }

  static Future<({String reason, bool dataErased})> revocationDetails() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      reason: prefs.getString('deviceRevocationReason') ?? 'unknown',
      dataErased: prefs.getBool('revokedDeviceDataErased') ?? false,
    );
  }

  static Future<bool> isLocallyRevoked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('deviceRevoked') ?? false;
  }

  static Future<void> clearLocalRevocationForReplacement() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('deviceRevoked');
    await prefs.remove('revokedDeviceId');
    await prefs.remove('deviceRevocationReason');
    await prefs.remove('revokedDeviceDataErased');
    await prefs.remove('revokedProfileStorageSuffix');
  }
}
