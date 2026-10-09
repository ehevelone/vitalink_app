import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FcmTokenService {
  static Future<String?> getToken({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await FirebaseMessaging.instance.getToken().timeout(timeout);
    } on TimeoutException {
      debugPrint('FCM_TOKEN_TIMEOUT');
      return null;
    } catch (error) {
      debugPrint('FCM_TOKEN_FAILED type=${error.runtimeType}');
      return null;
    }
  }
}
