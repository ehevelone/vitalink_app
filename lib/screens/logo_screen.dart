import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/app_state.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();

    _loadProfile();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerDeviceOnAppLoad();
    });

    _timer = Timer(const Duration(seconds: 3), _openMenu);
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

      setState(() {
        _p = null;
        _loading = false;
      });
    }
  }

  Future<void> _registerDeviceOnAppLoad() async {
    try {
      final store = SecureStore();

      final email = await store.getString('userEmail');
      final roleNullable = await store.getString('role');

      if (email == null || email.isEmpty) {
        _debug("Missing email — abort");
        return;
      }

      final role = roleNullable ?? 'user';

      // 🔥 Force permission request
      await FirebaseMessaging.instance.requestPermission();

      final fcmToken =
          await FirebaseMessaging.instance.getToken() ?? "NO_TOKEN";

      _debug("EMAIL: $email");
      _debug("ROLE: $role");
      _debug("TOKEN: $fcmToken");

      _debug("FORCING BACKEND CALL");

      final result = await ApiService.registerDeviceToken(
        email: email,
        fcmToken: fcmToken,
        role: role,
      );

      _debug("BACKEND RESPONSE: ${result['success']}");

      if (result['success'] == true) {
        await store.setString('lastDeviceToken', fcmToken);
      }
    } catch (e) {
      _debug("EXCEPTION: $e");
    }
  }

  void _debug(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("REG DEV: $msg")),
    );
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
    final String name = (_p?.fullName ?? '').trim();
    final bool hasName = !_loading && name.isNotEmpty;

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
            ],
          ),
        ),
      ),
    );
  }
}