import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/secure_store.dart';
import 'fcm_token_service.dart';

class NotificationService {
  // Called on app launch AND on token refresh
  static Future<void> initFCM() async {
    final store = SecureStore();
    final userId = await store.getString("userId");

    if (userId == null || userId.isEmpty) {
      debugPrint("⚠ FCM skipped — no logged-in user");
      return;
    }

    final token = await FcmTokenService.getToken();
    if (token != null) {
      await _sendToBackend(userId, token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint("FCM token refreshed");
      await _sendToBackend(userId, newToken);
    });
  }

  static Future<void> _sendToBackend(String userId, String token) async {
    await ApiService.registerDeviceToken(
      userId: userId,
      fcmToken: token,
    );
    debugPrint("FCM token registration completed");
  }
}
