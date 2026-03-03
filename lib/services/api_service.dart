import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _baseUrl =
      "https://vitalink-app.netlify.app/.netlify/functions";

  // -------------------------------------------------------------
  // 🔧 Internal POST helper (SAFE)
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final url = Uri.parse("$_baseUrl/$path");

      debugPrint("📡 POST → $url");
      debugPrint("📦 BODY → $body");

      final res = await http.post(
        url,
        headers: const {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      debugPrint("📥 STATUS ($path): ${res.statusCode}");
      debugPrint("📥 RAW BODY ($path): ${res.body}");

      if (res.statusCode != 200) {
        return {
          "success": false,
          "error": "Server returned ${res.statusCode}"
        };
      }

      if (res.body.isEmpty) {
        return {
          "success": false,
          "error": "Empty server response"
        };
      }

      final decoded = jsonDecode(res.body);

      if (decoded == null || decoded is! Map<String, dynamic>) {
        return {
          "success": false,
          "error": "Invalid server response"
        };
      }

      return decoded;
    } catch (e, st) {
      debugPrint("❌ API ERROR ($path): $e\n$st");
      return {"success": false, "error": e.toString()};
    }
  }

  // -------------------------------------------------------------
  // 🔹 Agent login
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> loginAgent({
    required String email,
    required String password,
    required String deviceId,
    bool replace = false,
  }) async {
    final res = await _postJson("check_agent", {
      "email": email,
      "password": password,
      "device_id": deviceId,
      "replace": replace,
    });

    if (res["success"] != true) {
      return {
        "success": false,
        "error": res["error"] ?? "Invalid credentials"
      };
    }

    if (res["agent"] == null) {
      return {
        "success": false,
        "error": "Agent data missing"
      };
    }

    return {"success": true, "agent": res["agent"]};
  }

  // -------------------------------------------------------------
  // 🔹 User login
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
    required String platform,
    required String deviceId,
    bool replace = false,
  }) async {
    final res = await _postJson("check_user", {
      "email": email,
      "password": password,
      "platform": platform,
      "device_id": deviceId,
      "replace": replace,
    });

    if (res["success"] != true) {
      return {
        "success": false,
        "error": res["error"] ?? "Invalid credentials"
      };
    }

    if (res["user"] == null) {
      return {
        "success": false,
        "error": "User data missing"
      };
    }

    return {"success": true, "user": res["user"]};
  }

  // -------------------------------------------------------------
  // 🔹 Register device token
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> registerDeviceToken({
    required String email,
    required String fcmToken,
    required String role,
  }) {
    return _postJson("register_device_v2", {
      "email": email,
      "role": role,
      "deviceToken": fcmToken,
      "platform": Platform.isIOS ? "ios" : "android",
    });
  }
}