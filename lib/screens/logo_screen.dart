import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPushAndRegister();
    });

    _timer = Timer(const Duration(seconds: 15), _openMenu);
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

      final email = await AppState.getEmail();
      final role = await AppState.getRole();

      if (email == null || role == null) return;

      await ApiService.registerDeviceToken(
        email: email,
        fcmToken: token,
        role: role,
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

    final loggedIn = await AppState.isLoggedIn();
    final role = await AppState.getRole();

    if (!mounted) return;

    if (!loggedIn) {
      Navigator.pushReplacementNamed(context, '/landing');
      return;
    }

    if (role == 'agent') {
      Navigator.pushReplacementNamed(context, '/agent_menu');
      return;
    }

    Navigator.pushReplacementNamed(context, '/menu');
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
              const SizedBox(height: 48),
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
