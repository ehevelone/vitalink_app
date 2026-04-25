import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/secure_store.dart';

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

        final agency = agent["agency_name"] ?? "your agency";
        final phone = agent["agency_phone"] ?? "";

await showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => AlertDialog(
    backgroundColor: const Color(0xFF111111),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    title: const Text(
      "Important Account Update",
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    ),
    content: Text(
      phone.isNotEmpty
          ? "Your insurance agent is no longer active.\n\n"
            "Please contact $agency at $phone for assistance."
          : "Your insurance agent is no longer active.\n\n"
            "Please contact $agency for assistance.",
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
          child: const Text("Call Agency"),
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
      final existing = await store.getString('qr_url');

      if (existing != null && existing.isNotEmpty) return;

      final userId = await store.getString("userId");
      if (userId == null) return;

      final res = await ApiService.getProfiles(userId);
      if (res["success"] != true) return;

      final profiles = res["profiles"];
      if (profiles == null || profiles.isEmpty) return;

      final token = profiles[0]["qr_token"];
      if (token == null || token.toString().isEmpty) return;

      final qrUrl =
          "https://myvitalink.app/emergency.html?token=$token";

      await store.setString('qr_url', qrUrl);

      debugPrint("✅ QR SAVED: $qrUrl");
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

      final token = await messaging.getToken();
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
    _timer?.cancel();

    try {
      final loggedIn = await AppState.isLoggedIn();
      final role = await AppState.getRole();

      if (!mounted) return;

      if (!loggedIn) {
        Navigator.pushReplacementNamed(context, '/landing');
        return;
      }

      // 🔥 CHECK HERE
      final allowed = await _checkAgentStatus();
      if (!allowed) return;

      if (role == 'agent') {
        Navigator.pushReplacementNamed(context, '/agent_menu');
        return;
      }

      Navigator.pushReplacementNamed(context, '/menu');
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/landing');
    }
  }

  void _openEmergencyScreen() {
    _timer?.cancel();
    Navigator.pushReplacementNamed(context, '/emergency');
  }

  @override
  Widget build(BuildContext context) {
    final hasName = !_loading && _p?.fullName.isNotEmpty == true;
    final name = hasName ? _p!.fullName : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: InkWell(
        onTap: _openMenu,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/vitalink-logo-1.png',
                width: 220,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),

              if (_loading)
                const CircularProgressIndicator(color: Colors.white70)
              else if (hasName) ...[
                Text(
                  "Welcome, $name",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
              ],

              const Text(
                'TAP ANYWHERE TO OPEN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),

              const SizedBox(height: 24),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  "Emergency profiles are encrypted and securely stored for QR access in emergencies.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
                        color: Colors.redAccent.withOpacity(0.4),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                      SizedBox(height: 12),
                      Text(
                        "EMERGENCY",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "TAP FOR INFO",
                        style: TextStyle(
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
    );
  }
}