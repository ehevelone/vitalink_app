import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _baseUrl =
      "https://vitalink-app.netlify.app/.netlify/functions";

  // -------------------------------------------------------------
  // 🔧 Internal POST helper (HARDENED FOR iOS)
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

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {
        "success": false,
        "error": "Invalid server response"
      };
    } catch (e, st) {
      debugPrint("❌ API ERROR ($path): $e\n$st");
      return {"success": false, "error": e.toString()};
    }
  }

  // -------------------------------------------------------------
  // 🔎 Get User's Assigned Agent
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> getUserAgent(String email) {
    return _postJson("get_user_agent", {"email": email});
  }

  // -------------------------------------------------------------
  // 🔎 Get full agent profile
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> getAgentProfile({
    required String email,
  }) {
    return _postJson("get_agent_profile", {"email": email});
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
      return {"success": false, "error": res["error"] ?? "Invalid credentials"};
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
  }) async {
    final res = await _postJson("check_user", {
      "email": email,
      "password": password,
      "platform": platform,
    });

    if (res["success"] != true || res["user"] == null) {
      return {"success": false, "error": res["error"] ?? "Invalid credentials"};
    }

    return {"success": true, "user": res["user"]};
  }

  // -------------------------------------------------------------
  // 🔹 Register user
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> registerUser({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String promoCode,
    required String platform,
  }) {
    return _postJson("register_user", {
      "firstName": firstName,
      "lastName": lastName,
      "email": email,
      "phone": phone,
      "password": password,
      "promoCode": promoCode,
      "platform": platform,
    });
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
  static Future<Map<String, dynamic>> requestPasswordReset({
    required String emailOrPhone,
    required String role,
  }) {
    return _postJson("request_reset", {
      "emailOrPhone": emailOrPhone,
      "role": role,
    });
  }

  // -------------------------------------------------------------
  // 🔹 Complete password reset
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> resetPassword({
    required String emailOrPhone,
    required String code,
    required String newPassword,
    required String role,
  }) {
    return _postJson("reset_password", {
      "emailOrPhone": emailOrPhone,
      "code": code,
      "newPassword": newPassword,
      "role": role,
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
      "agencyName": agencyName,
      "agencyAddress": agencyAddress,
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

  // -------------------------------------------------------------
  // 🔎 Resolve agent by QR / agent code
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> resolveAgentByCode(String code) async {
    final res = await _postJson("resolve_agent_code", {
      "code": code,
    });

    if (res["success"] != true || res["agent"] == null) {
      return {
        "success": false,
        "error": res["error"] ?? "Invalid agent code",
      };
    }

    return {
      "success": true,
      "agent": res["agent"],
    };
  }
}