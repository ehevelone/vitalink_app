import 'dart:async';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/api_service.dart';
import '../services/device_security_service.dart';
import '../services/app_state.dart';
import '../services/secure_store.dart';
import '../services/fcm_token_service.dart';

class LogoScreen extends StatefulWidget {
  const LogoScreen({super.key});

  @override
  State<LogoScreen> createState() => _LogoScreenState();
}

class _LogoScreenState extends State<LogoScreen> {
  Timer? _timer;
  late final DataRepository _repo = DataRepository();

  Profile? _p;
  bool _loading = true;
  bool _deviceRegistered = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _loadProfile();
    _initQR();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPushAndRegister();
    });

    _timer = Timer(const Duration(seconds: 3), _openMenu);
  }

  // 🔥 FIXED AGENT STATUS CHECK
  Future<bool> _checkAgentStatus() async {
    try {
      final role = await AppState.getRole();
      final userId = await SecureStore().getString("userId");

      // 🔥 SAFER CHECK
      if (role == "agent" && userId == null) {
        return true;
      }

      final email = await AppState.getEmail();
      if (email == null || email.isEmpty) return true;

      final res = await ApiService.getUserAgent(email);

      if (res["success"] != true) return true;

      final agent = res["agent"];
      if (agent == null) return true;

      if (agent["active"] == false) {
        if (!mounted) return false;

        final agency =
            agent["agency_name"] ?? AppStrings.of(context).yourAgency;
        final phone = agent["agency_phone"] ?? "";

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF111111),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              AppStrings.of(context).importantAccountUpdate,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              phone.isNotEmpty
                  ? AppStrings.of(context)
                      .agentInactiveBody('$agency', '$phone')
                  : AppStrings.of(context).agentInactiveBodyNoPhone('$agency'),
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              if (phone.isNotEmpty)
                FilledButton(
                  onPressed: () async {
                    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
                    final uri = Uri.parse("tel:$cleanPhone");
                    await launchUrl(uri);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(AppStrings.of(context).callAgency),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );

        return false;
      }

      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _initQR() async {
    try {
      final store = SecureStore();
      final activeProfile = await _repo.loadProfile();
      final cacheKey = 'qr_url:${activeProfile.id}';
      final existing = await store.getString(cacheKey);

      if (existing != null && existing.isNotEmpty) return;

      final userId = await store.getString("userId");
      if (userId == null) return;

      final res = await ApiService.getUserProfiles(userId);
      if (res["success"] != true) return;

      final profiles = res["profiles"];
      if (profiles == null || profiles.isEmpty) return;

      final matchingProfile = profiles
          .cast<dynamic>()
          .where((profile) =>
              profile is Map && profile['id']?.toString() == activeProfile.id)
          .firstOrNull;
      final token = matchingProfile?["qr_token"];
      if (token == null || token.toString().isEmpty) return;

      final qrUrl = "https://myvitalink.app/emergency.html?token=$token";

      await store.setString(cacheKey, qrUrl);

      debugPrint("QR saved");
    } catch (e) {
      debugPrint("❌ QR INIT ERROR: $e");
    }
  }

  Future<void> _initPushAndRegister() async {
    if (_deviceRegistered) return;

    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await FcmTokenService.getToken();
      if (token == null) return;

      final userId = await SecureStore().getString("userId");
      if (userId == null) return;

      await ApiService.registerDeviceToken(
        userId: userId,
        fcmToken: token,
      );

      _deviceRegistered = true;
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _repo.loadProfile();
      if (!mounted) return;

      setState(() {
        _p = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _openMenu() async {
    if (_navigated) return; // 🔥 THIS LINE
    _navigated = true; // 🔥 THIS LINE
    _timer?.cancel();

    try {
      final loggedIn = await AppState.isLoggedIn();
      final role = await AppState.getRole();
      final userSessionToken =
          await SecureStore().getString("userSessionToken");

      if (!mounted) return;

      if (!loggedIn) {
        Navigator.pushReplacementNamed(context, '/landing');
        return;
      }

      if (role == 'user' &&
          (userSessionToken == null || userSessionToken.isEmpty)) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      if (role == 'user') {
        final deviceActive = await DeviceSecurityService.checkCurrentDevice();
        if (!mounted) return;
        if (!deviceActive) {
          Navigator.pushReplacementNamed(context, '/device_disabled');
          return;
        }
      }

      // 🔥 CHECK HERE
      final allowed = await _checkAgentStatus();
      if (!allowed) return;
      if (!mounted) return;

      if (role == 'agent') {
        Navigator.pushReplacementNamed(context, '/agent_menu');
        return;
      }

      final userId = await SecureStore().getString('userId');
      if (userId != null) {
        final accessResult = await ApiService.getAccountAccess(userId);
        final access = Map<String, dynamic>.from(
          accessResult['access'] as Map? ?? const {},
        );
        if (accessResult['success'] == true && access['needsReview'] == true) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/account_access');
          return;
        }
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/menu');
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/landing');
    }
  }

  void _handleOpenTap() {
    _timer?.cancel();
    _openMenu();
  }

  void _openEmergencyScreen() {
    if (_navigated) return;
    _navigated = true;
    _timer?.cancel();
    Navigator.pushReplacementNamed(context, '/emergency');
  }

  @override
  Widget build(BuildContext context) {
    final hasName = !_loading && _p?.fullName.isNotEmpty == true;
    final name = hasName ? _p!.fullName : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _handleOpenTap,
        child: SizedBox.expand(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/vitalink-logo-1.png',
                  width: 220,
                  cacheWidth: 660,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 28),
                if (_loading)
                  const CircularProgressIndicator(color: Colors.white70)
                else if (hasName) ...[
                  Text(
                    AppStrings.of(context).welcomeName('$name'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(
                    AppStrings.of(context).emergencyProfilesEncrypted,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _openEmergencyScreen,
                  child: Container(
                    width: 240,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.redAccent,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "EMERGENCY",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppStrings.of(context).tapForInfo,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
