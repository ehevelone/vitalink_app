import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/deep_link_service.dart'; // ✅ FIX ADDED

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {

  static const Color vitalinkBlue = Color(0xFF79CAE3);

  String? activationCode;

  bool _checkedRoute = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);

    if (route != null) {
      final args = route.settings.arguments;

      if (args is Map && args["code"] != null) {
        activationCode = args["code"];
      }
    }

    activationCode ??= VitaLinkDeepLink.code;

    if (!_checkedRoute) {
      _checkedRoute = true;
    }
  }

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

              const SizedBox(height: 8),

              const Text(
                "Choose the account type that matches how you use VitaLink.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 24),

              _registerOption(
                icon: Icons.family_restroom,
                title: "Create Client Account",
                subtitle: "For VitaLink users and families",
                color: Colors.green,
                onPressed: () {
                  Navigator.pop(ctx);

                  Navigator.pushReplacementNamed(
                    context,
                    '/terms_user',
                    arguments: {"code": activationCode},
                  );
                },
              ),

              const SizedBox(height: 15),

              _registerOption(
                icon: Icons.business_center,
                title: "Activate Agent Portal",
                subtitle:
                    "Insurance agents must activate access through myvitalink.app",
                color: vitalinkBlue,
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAgentActivationDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _registerOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.8)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.black),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVitaLinkWebsite() async {
    final url = Uri.parse("https://myvitalink.app/agent-portal-activation");
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _showAgentActivationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Agent Portal Activation",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Insurance agent accounts are activated through the VitaLink website before app access is enabled.\n\n"
          "Have you already activated your agent account through myvitalink.app?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/agent_login');
            },
            child: const Text("I Already Activated"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: vitalinkBlue,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _openVitaLinkWebsite();
            },
            child: const Text("Open myvitalink.app"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: SafeArea(
          child: Column(
            children: [

              Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [

                          const SizedBox(height: 60),

                          const Text(
                            "Welcome To",
                            style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.bold,
                              color: vitalinkBlue,
                            ),
                          ),

                          const SizedBox(height: 30),

                          Image.asset(
                            'assets/images/vitalink-logo-2.png',
                            width: 240,
                          ),

                          const SizedBox(height: 70),

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

                          const SizedBox(height: 24),

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

                          const SizedBox(height: 60),

                        ],
                      ),
                    ),
                  ),
                ),
              ),

              Container(
                width: double.infinity,
                color: Colors.black,
                child: Image.asset(
                  'assets/images/landing-bottom.png',
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}
