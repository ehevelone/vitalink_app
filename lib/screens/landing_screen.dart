// lib/screens/landing_screen.dart
import 'package:flutter/material.dart';
import '../services/secure_store.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  static const Color vitalinkBlue = Color(0xFF79CAE3);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkStoredSession();
  }

  /// ✅ Landing ONLY redirects if user is STILL logged in
  Future<void> _checkStoredSession() async {
    final store = SecureStore();
    final role = await store.getString('role');
    final loggedIn = await store.getBool('loggedIn') ?? false;

    if (!mounted) return;

    // ✅ Logged in → Splash (Landing is skipped entirely)
    if (role != null && loggedIn) {
      Navigator.pushReplacementNamed(context, '/splash');
      return;
    }

    // ✅ Not logged in → stay on Landing
    setState(() => _loading = false);
  }

  Future<void> _chooseAgent() async {
    final store = SecureStore();
    await store.setString('role', 'agent');
    Navigator.pushReplacementNamed(context, '/terms_agent');
  }

  Future<void> _chooseUser() async {
    final store = SecureStore();
    await store.setString('role', 'user');
    Navigator.pushReplacementNamed(context, '/terms_user');
  }

  void _showLoginPopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: const Color(0xFFF2ECF7),
          title: const Text(
            "Already Registered?",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Choose your login type:",
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(dialogCtx).pop();
                      Navigator.pushNamed(context, '/login');
                    },
                    child: const Text(
                      "User Login",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.normal,
                        color: Color(0xFF4A3AFF),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(dialogCtx).pop();
                      Navigator.pushNamed(context, '/agent_login');
                    },
                    child: const Text(
                      "Agent Login",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.normal,
                        color: Color(0xFF4A3AFF),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text(
                  "Welcome To",
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    color: vitalinkBlue,
                  ),
                ),
                const SizedBox(height: 20),
                Image.asset('assets/images/vitalink-logo-2.png', width: 240),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vitalinkBlue,
                    minimumSize: const Size(double.infinity, 55),
                  ),
                  icon: const Icon(Icons.badge, color: Colors.black),
                  label: const Text(
                    "I'm an Agent",
                    style: TextStyle(fontSize: 18, color: Colors.black),
                  ),
                  onPressed: _chooseAgent,
                ),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(double.infinity, 55),
                  ),
                  icon: const Icon(Icons.person, color: Colors.black),
                  label: const Text(
                    "I'm a User",
                    style: TextStyle(fontSize: 18, color: Colors.black),
                  ),
                  onPressed: _chooseUser,
                ),
                const SizedBox(height: 35),
                const Text(
                  "Already Registered?",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: vitalinkBlue,
                  ),
                ),
                GestureDetector(
                  onTap: _showLoginPopup,
                  child: const Text(
                    "Log In Here",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: vitalinkBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
