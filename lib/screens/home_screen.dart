import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final profile = await _repo.loadProfile();
    setState(() {
      _p = profile;
      _loading = false;
    });
  }

  void _openMenu(BuildContext context) {
    Navigator.of(context).pushReplacementNamed('/menu');
  }

  void _openEmergency(BuildContext context) {
    Navigator.of(context).pushReplacementNamed('/emergency_view');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final title = _p!.fullName.isNotEmpty
        ? "VitaLink Home for ${_p!.fullName}"
        : "VitaLink Home";

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: Colors.black, // Matches splash branding
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo (tappable)
            GestureDetector(
              onTap: () => _openMenu(context),
              child: Image.asset(
                'assets/images/vitalink-logo-1.png',
                width: 220,
                cacheWidth: 660,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 24),

            // “Tap to open” text
            const Text(
              'Tap logo to open menu',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),

            // 911 Emergency Info button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.warning, size: 20),
              label: const Text("911 Emergency Info"),
              onPressed: () => _openEmergency(context),
            ),
            const SizedBox(height: 16),

            // Open menu button (alternative to tapping logo)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: const Text("Open Menu"),
              onPressed: () => _openMenu(context),
            ),
          ],
        ),
      ),
    );
  }
}
