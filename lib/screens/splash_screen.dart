import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/secure_store.dart';
import '../services/data_repository.dart';

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
      final loggedIn = await store.getBool('userLoggedIn') ?? false;

      if (!mounted) return;

      if (loggedIn) {
        // 🔒 Validate profile integrity before routing
        final repo = DataRepository(store);
        final profile = await repo.loadProfile();

        if (profile == null) {
          // Corrupted or missing profile → auto-heal
          await store.clear();
          Navigator.pushReplacementNamed(context, '/landing');
          return;
        }

        Navigator.pushReplacementNamed(context, '/logo');
        return;
      }

      Navigator.pushReplacementNamed(context, '/landing');
    } catch (_) {
      if (!mounted) return;
      await store.clear();
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
