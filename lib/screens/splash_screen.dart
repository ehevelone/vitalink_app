import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/secure_store.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();

    // Route AFTER first frame to avoid plugin race conditions
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _route();
    });
  }

  Future<void> _route() async {
    final store = SecureStore();

    try {
      final role = await store.getString('role');
      final loggedIn = await store.getBool('loggedIn') ?? false;

      if (!mounted) return;

      // ✅ Logged in → branding/logo flow
      if (role != null && loggedIn) {
        Navigator.pushReplacementNamed(context, '/logo');
        return;
      }

      // ✅ Not logged in → landing
      Navigator.pushReplacementNamed(context, '/landing');
    } catch (_) {
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
