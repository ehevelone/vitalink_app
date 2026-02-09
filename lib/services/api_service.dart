// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  /// ✅ Netlify Functions base URL (THIS IS CORRECT)
  static const String _baseUrl =
      "https://vitalink-app.netlify.app/.netlify/functions";

  // -------------------------------------------------------------
  // 🔧 Internal POST helper
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
        headers: const {
          "Content-Type": "application/json",
        },
        body: jsonEncode(body),
      );

      debugPrint("📥 STATUS (${path}): ${res.statusCode}");
      debugPrint("📥 RAW BODY (${path}): ${res.body}");

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      return decoded;
    } catch (e, st) {
      debugPrint("❌ API ERROR ($path): $e\n$st");
      return {"success": false, "error": e.toString()};
    }
  }

  // -------------------------------------------------------------
  // 🔹 Insurance card parsing
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> parseInsurance(File image) async {
    final bytes = await image.readAsBytes();
    final base64 = base64Encode(bytes);
    return _postJson("parse_insurance", {"imageBase64": base64});
  }

  // -------------------------------------------------------------
  // 🔹 Agent unlock claim
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> claimAgentUnlock({
    required String unlockCode,
    required String email,
    required String password,
    required String npn,
    String? phone,
    String? name,
  }) {
    return _postJson("claim_agent_unlock", {
      "unlockCode": unlockCode,
      "email": email,
      "password": password,
      "npn": npn,
      "phone": phone,
      "name": name,
    });
  }

  // -------------------------------------------------------------
  // 🔹 Agent login
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> loginAgent({
    required String email,
    required String password,
  }) async {
    final res = await _postJson("check_agent", {
      "email": email,
      "password": password,
    });

    if (res["success"] != true || res["agent"] == null) {
      return {
        "success": false,
        "error": res["error"] ?? "Invalid credentials",
      };
    }

    return {
      "success": true,
      "agent": res["agent"],
    };
  }

  // -------------------------------------------------------------
  // 🔹 User login
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
    required String platform,
  }) async {
    final res = await _postJson("check_user", {
      "email": email,
      "password": password,
      "platform": platform,
    });

    if (res["success"] != true || res["user"] == null) {
      return {
        "success": false,
        "error": res["error"] ?? "Invalid credentials",
      };
    }

    return {
      "success": true,
      "user": res["user"],
    };
  }

  // -------------------------------------------------------------
  // 🔹 Promo lookup
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> verifyPromo({
    required String username,
    required String promoCode,
  }) {
    return _postJson("vpc", {
      "username": username,
      "promoCode": promoCode,
    });
  }

  // -------------------------------------------------------------
  // 🔹 Generate agent unlock code
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> issueAgentCode({
    required String masterKey,
    String? requestedEmail,
    String? requestedName,
    String? requestedNpn,
  }) {
    return _postJson("generate_agent_unlock", {
      "masterKey": masterKey,
      "email": requestedEmail,
      "name": requestedName,
      "npn": requestedNpn,
    });
  }

  // -------------------------------------------------------------
  // 🔹 Request password reset
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> requestPasswordReset(
      String emailOrPhone) {
    return _postJson("request_reset", {"emailOrPhone": emailOrPhone});
  }

  // -------------------------------------------------------------
  // 🔹 Complete password reset
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> resetPassword({
    required String emailOrPhone,
    required String code,
    required String newPassword,
  }) {
    return _postJson("reset_password", {
      "emailOrPhone": emailOrPhone,
      "code": code,
      "newPassword": newPassword,
    });
  }

  // -------------------------------------------------------------
  // 🔥 Get agent promo code
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> getAgentPromoCode(String email) {
    return _postJson("get_agent_promo", {"email": email});
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
      "platform": "android",
    });
  }

  // -------------------------------------------------------------
  // 🔔 Send notification
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> sendNotification({
    required String agentEmail,
  }) {
    return _postJson("send_notification", {"agentEmail": agentEmail});
  }

  // -------------------------------------------------------------
  // 🧑‍💼 Update agent profile
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> updateAgentProfile({
    required String email,
    String? name,
    String? phone,
    String? npn,
    String? agencyName,
    String? agencyAddress,
    String? password,
  }) {
    final body = {
      "email": email,
      "name": name,
      "phone": phone,
      "npn": npn,
      "agency_name": agencyName,
      "agency_address": agencyAddress,
      "password": password,
    }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

    return _postJson("update_agent_profile", body);
  }

  // -------------------------------------------------------------
  // 👤 Update user profile
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> updateUserProfile({
    required String currentEmail,
    required String email,
    String? name,
    String? phone,
    String? password,
  }) {
    final body = {
      "currentEmail": currentEmail,
      "email": email,
      "name": name,
      "phone": phone,
      "password": password,
    }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

    return _postJson("update_user_profile", body);
  }
}
