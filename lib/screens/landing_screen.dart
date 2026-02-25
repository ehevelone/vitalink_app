import 'package:flutter/material.dart';
import '../services/app_state.dart';

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

  Future<void> _checkStoredSession() async {
    final loggedIn = await AppState.isLoggedIn();

    if (!mounted) return;

    if (loggedIn) {
      Navigator.pushReplacementNamed(context, '/logo');
      return;
    }

    setState(() => _loading = false);
  }

  // ------------------------
  // LOGIN POPUP
  // ------------------------
  void _showLoginPopup() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Log In",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 55),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(context, '/login');
                },
                child: const Text(
                  "User Login",
                  style: TextStyle(fontSize: 18, color: Colors.black),
                ),
              ),

              const SizedBox(height: 15),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: vitalinkBlue,
                  minimumSize: const Size(double.infinity, 55),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(context, '/agent_login');
                },
                child: const Text(
                  "Agent Login",
                  style: TextStyle(fontSize: 18, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------
  // REGISTER POPUP
  // ------------------------
  void _showRegisterPopup() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 55),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await AppState.setRole('user');
                  Navigator.pushReplacementNamed(context, '/terms_user');
                },
                child: const Text(
                  "Create User Account",
                  style: TextStyle(fontSize: 18, color: Colors.black),
                ),
              ),

              const SizedBox(height: 15),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: vitalinkBlue,
                  minimumSize: const Size(double.infinity, 55),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await AppState.setRole('agent');
                  Navigator.pushReplacementNamed(context, '/terms_agent');
                },
                child: const Text(
                  "Create Agent Account",
                  style: TextStyle(fontSize: 18, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------
  // UI
  // ------------------------
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
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      const Text(
                        "Welcome To",
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                          color: vitalinkBlue,
                        ),
                      ),

                      const SizedBox(height: 20),

                      Image.asset(
                        'assets/images/vitalink-logo-2.png',
                        width: 240,
                      ),

                      const SizedBox(height: 50),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          minimumSize: const Size(double.infinity, 55),
                        ),
                        onPressed: _showLoginPopup,
                        child: const Text(
                          "Log In to Your Account",
                          style: TextStyle(fontSize: 18, color: Colors.black),
                        ),
                      ),

                      const SizedBox(height: 20),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: vitalinkBlue,
                          minimumSize: const Size(double.infinity, 55),
                        ),
                        onPressed: _showRegisterPopup,
                        child: const Text(
                          "Register for an Account",
                          style: TextStyle(fontSize: 18, color: Colors.black),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Branding Image
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Image.asset(
                'assets/images/landing-bottom.png',
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}