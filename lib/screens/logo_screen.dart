import 'dart:async';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class LogoScreen extends StatefulWidget {
  const LogoScreen({super.key});

  @override
  State<LogoScreen> createState() => _LogoScreenState();
}

class _LogoScreenState extends State<LogoScreen> {
  Timer? _timer;
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());

    _loadProfile();

    // ✅ EXACT dwell time (15s)
    _timer = Timer(const Duration(seconds: 15), _openMenu);
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

  /// ✅ ROUTING — NEVER LOOP
  Future<void> _openMenu() async {
    _timer?.cancel();

    final store = SecureStore();
    final role = await store.getString('role');

    if (!mounted) return;

    if (role == 'agent') {
      Navigator.pushReplacementNamed(context, '/agent_menu');
      return;
    }

    if (role == 'user') {
      Navigator.pushReplacementNamed(context, '/menu');
      return;
    }

    Navigator.pushReplacementNamed(context, '/landing');
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
              // ✅ LOGO
              Image.asset(
                'assets/images/vitalink-logo-1.png',
                width: 220,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 28),

              // ✅ PROFILE / LOADING
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

              // ✅ TAP ANYWHERE (PROMINENT)
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

              // 🔴 BIG SQUARE EMERGENCY BUTTON
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
