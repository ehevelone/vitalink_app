import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/data_repository.dart';
import '../models.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    if (_routed) return;
    _routed = true;

    try {
      // 🔥 TEMP TEST — bypass AppState
      final loggedIn = false;

      if (!mounted) return;

      // 🔹 Not logged in → Landing
      if (!loggedIn) {
        Navigator.pushReplacementNamed(context, '/landing');
        return;
      }

      // 🔹 Try loading local profile
      Profile? profile;
      try {
        final repo = DataRepository();
        profile = await repo.loadProfile();
      } catch (_) {
        profile = null;
      }

      if (!mounted) return;

      if (profile == null) {
        Navigator.pushReplacementNamed(context, '/landing');
        return;
      }

      Navigator.pushReplacementNamed(context, '/logo');

    } catch (e, st) {
      debugPrint("Splash crash: $e");
      debugPrint("$st");

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/landing');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image(
              image: AssetImage('assets/images/vitalink-logo-1.png'),
              height: 120,
            ),
            SizedBox(height: 16),
            CircularProgressIndicator(color: Colors.white70),
          ],
        ),
      ),
    );
  }
}