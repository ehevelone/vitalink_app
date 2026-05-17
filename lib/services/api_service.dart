import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

// 🔥 ADDED FOR PROFILE SYNC
import '../services/secure_store.dart';
import '../services/data_repository.dart';

class ApiService {
  static const String _baseUrl =
      "https://vitalink-app.netlify.app/.netlify/functions";

  // -------------------------------------------------------------
  // 🔥 UUID FIX (KEEP FOR OTHER USES)
  // -------------------------------------------------------------
  static String _ensureUuid(String? id) {
    if (id == null || id.isEmpty) return const Uuid().v4();

    final uuidRegex = RegExp(r'^[0-9a-fA-F-]{36}$');

    if (uuidRegex.hasMatch(id)) return id;

    return const Uuid().v5(Uuid.NAMESPACE_URL, id);
  }

 // -------------------------------------------------------------
// 🔧 Internal POST helper (SAFE)
// -------------------------------------------------------------
static Future<Map<String, dynamic>> _postJson(
  String path,
  Map<String, dynamic> body,
) async {
  try {
    final url = Uri.parse("$_baseUrl/$path");
    debugPrint("🌐 FULL URL → $url");

    debugPrint("📡 POST → $url");
    debugPrint("📦 BODY → $body");

    final res = await http.post(
      url,
      headers: const {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    debugPrint("📥 STATUS ($path): ${res.statusCode}");
    debugPrint("📥 RAW BODY ($path): ${res.body}");

    // 🔥 CRITICAL FIX:
    // Always return backend JSON — even on 403
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);

        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (e) {
        debugPrint("⚠️ JSON decode failed: $e");
      }
    }

    // fallback only if response is unusable
    return {
      "success": false,
      "error": "Server returned ${res.statusCode}"
    };

  } catch (e, st) {
    debugPrint("❌ API ERROR ($path): $e\n$st");
    return {"success": false, "error": e.toString()};
  }

}

static Future<String?> _userSessionToken() async {
  return SecureStore().getString("userSessionToken");
}

static Future<String?> _agentSessionToken() async {
  return SecureStore().getString("agentSessionToken");
}

static Future<Map<String, dynamic>> _postJsonWithUserSession(
  String path,
  Map<String, dynamic> body,
) async {
  final token = await _userSessionToken();
  return _postJson(path, {
    ...body,
    if (token != null && token.isNotEmpty) "sessionToken": token,
  });
}

static Future<Map<String, dynamic>> _postJsonWithAgentSession(
  String path,
  Map<String, dynamic> body,
) async {
  final token = await _agentSessionToken();
  return _postJson(path, {
    ...body,
    if (token != null && token.isNotEmpty) "agentSessionToken": token,
  });
}
  static Future<Map<String, dynamic>> saveUserProfiles({
    required String userId,
    required List<Map<String, dynamic>> profiles,
  }) async {
    final body = {
      "id": userId, // ✅ FIXED
      "profiles": profiles,
    };

    debugPrint("🚀 SAVE USER PROFILES: $body");

    return await _postJsonWithUserSession("save_user_profiles", body);
  }

  // -------------------------------------------------------------
  // 🔥 GET PROFILES (FOR QR TOKEN)
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> getProfiles(String id) async {
    return await _postJson("get_profiles", {
      "id": id, // ✅ FIXED
    });
  }

  static Future<Map<String, dynamic>> getUserProfiles(String userId) async {
    return await _postJsonWithUserSession("get_profiles", {
      "user_id": userId,
    });
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
    return _postJsonWithAgentSession("get_agent_profile", {"email": email});
  }

  // -------------------------------------------------------------
  // 🔹 Insurance card parsing
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> parseInsurance(File image) async {
    final bytes = await image.readAsBytes();
    final base64 = base64Encode(bytes);
    final store = SecureStore();
    final userId = await store.getString("userId");

    return _postJsonWithUserSession("parse_insurance", {
      "imageBase64": base64,
      if (userId != null && userId.isNotEmpty) "userId": userId,
    });
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
  String? deviceId,
  bool replace = false,
}) async {
  final body = {
    "email": email,
    "password": password,
    "replace": replace,
  };

  if (deviceId != null) {
    body["device_id"] = deviceId;
  }

  final res = await _postJson("check_agent", body);

  return res; // 🔥 DO NOT MODIFY RESPONSE
}

// -------------------------------------------------------------
// 🔥 NEW — CREATE AGENT CHECKOUT (PUBLIC)
// -------------------------------------------------------------
static Future<Map<String, dynamic>> createAgentCheckout({
  required String email,
}) async {
  final body = {
    "email": email,
    "plan": "app_crm",
  };

  final res = await _postJson("vl-agent-checkout", body);

  return res;
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
  // 🔎 Activation lookup
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> lookupActivation(String code) {
    return _postJson("vl-get-activation-details", {
      "code": code,
    });
  }

  // -------------------------------------------------------------
  // 🔹 Promo lookup
  // -------------------------------------------------------------
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
    return _postJsonWithAgentSession("get_agent_promo", {"email": email});
  }

  // -------------------------------------------------------------
  // 🔹 Register device token
  // -------------------------------------------------------------
static Future<Map<String, dynamic>> registerDeviceToken({
  required String userId,
  required String fcmToken,
  String? platform,
}) {
  return _postJsonWithUserSession("register_device_v2", {
    "user_id": int.parse(userId),   // 🔥 THIS FIXES IT
    "deviceToken": fcmToken,
    "platform": platform ?? (Platform.isIOS ? "ios" : "android"),
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
    String? agencyPhone,
    String? password,
  }) {
    final body = {
      "email": email,
      "name": name,
      "phone": phone,
      "npn": npn,
      "agencyName": agencyName,
      "agencyAddress": agencyAddress,
      "agencyPhone": agencyPhone,
      "password": password,
    }..removeWhere((k, v) => v == null || v.trim().isEmpty);

    return _postJsonWithAgentSession("update_agent_profile", body);
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
    }..removeWhere((k, v) => v == null || v.trim().isEmpty);

    return _postJson("update_user_profile", body);
  }

  // -------------------------------------------------------------
  // 🔎 Mark agent as reviewed
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> markReviewed({
    required String email,
  }) {
    return _postJson("mark_reviewed", {
      "email": email.trim(),
    });
  }

  // -------------------------------------------------------------
  // 🔎 Resolve agent by code
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

  // -------------------------------------------------------------
  // 🆕 GET AGENT CLIENTS
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> getAgentClients({
    required int agentId,
  }) {
    return _postJsonWithAgentSession("get_agent_clients", {
      "agentId": agentId,
    });
  }

  static Future<Map<String, dynamic>> getAgentItems({
    required int agentId,
    int? clientId,
  }) {
    final body = {
      "agentId": agentId,
      if (clientId != null) "clientId": clientId,
    };

    return _postJsonWithAgentSession("get_agent_items", body);
  }

  static Future<Map<String, dynamic>> saveAgentItem({
    required int agentId,
    required int clientId,
    required String itemType,
    required String text,
  }) {
    return _postJsonWithAgentSession("save_agent_item", {
      "agentId": agentId,
      "clientId": clientId,
      "itemType": itemType,
      "text": text,
    });
  }

  static Future<Map<String, dynamic>> deleteAgentItem({
    required int agentId,
    required int itemId,
  }) {
    return _postJsonWithAgentSession("delete_agent_item", {
      "agentId": agentId,
      "itemId": itemId,
    });
  }

  static Future<Map<String, dynamic>> syncAppClientToCrm({
    required int agentId,
    required int clientId,
    Map<String, dynamic>? client,
    Map<String, dynamic>? profile,
  }) {
    final body = {
      "agentId": agentId,
      "clientId": clientId,
      if (client != null) "client": client,
      if (profile != null) "profile": profile,
    };

    return _postJsonWithAgentSession("sync_app_client_to_crm", body);
  }

  // -------------------------------------------------------------
  // 🔥 SYNC USER PROFILES
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> syncProfilesToServer() async {
    try {
      final store = SecureStore();
      final repo = DataRepository(store);

      final userId = await store.getString("userId");

      if (userId == null) {
        debugPrint("❌ No userId found — skipping profile sync");
        return {"success": false};
      }

      final profiles = await repo.loadAllProfiles();

      if (profiles.isEmpty) {
        debugPrint("⚠️ No profiles to sync");
        return {"success": false};
      }

      final fixedProfiles = profiles.map((p) {
        final json = p.toJson();
        json["id"] = _ensureUuid(p.id);
        return json;
      }).toList();

      final body = {
        "id": userId, // ✅ FIXED
        "profiles": fixedProfiles,
      };

      debugPrint("🚀 SENDING PROFILES: $body");

      return await _postJsonWithUserSession("save_user_profiles", body);
    } catch (e, st) {
      debugPrint("❌ Profile Sync Error: $e\n$st");
      return {"success": false, "error": e.toString()};
    }
  }
}
