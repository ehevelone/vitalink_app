import 'dart:async';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
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

      // 🔒 HARD SAFE DEFAULTS
      final safeRole = role ?? "user";

      if (safeRole == 'agent') {
        Navigator.pushReplacementNamed(context, '/agent_menu');
        return;
      }

      Navigator.pushReplacementNamed(context, '/menu');
    } catch (e) {
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
                const CircularProgressIndicator(
                  color: Colors.white70,
                )
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
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      "EMERGENCY",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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