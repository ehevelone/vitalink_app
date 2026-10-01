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
    final eraseData = normalizedReason == 'lost' || normalizedReason == 'stolen';
    if (eraseData) {
      await DataRepository().clearLocalProfiles();
    }
    await SecureStore().clearAuth();
    await AppState.clearAuth();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('deviceRevoked', true);
    await prefs.setString('revokedDeviceId', deviceId);
    await prefs.setString('deviceRevocationReason', normalizedReason);
    await prefs.setBool('revokedDeviceDataErased', eraseData);
  }

  static Future<void> erasePreservedLocalData() async {
    await DataRepository().clearLocalProfiles();
    final prefs = await SharedPreferences.getInstance();
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
  }
}
