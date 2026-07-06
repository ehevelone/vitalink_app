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

  Widget _scrollableDialog({required Widget child}) {
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: child,
      ),
    );
  }

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
        child: _scrollableDialog(
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
        child: _scrollableDialog(
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
                    _showClientActivationDialog();
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

  Future<void> _openClientActivationPage() async {
    final url = Uri.parse("https://myvitalink.app/activate");
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _continueClientRegistration() {
    Navigator.pushReplacementNamed(
      context,
      '/terms_user',
      arguments: {"code": activationCode},
    );
  }

  Widget _dialogActionButton({
    required String label,
    required VoidCallback onPressed,
    required bool primary,
  }) {
    if (primary) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: vitalinkBlue,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: vitalinkBlue,
        side: const BorderSide(color: vitalinkBlue),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showClientActivationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: _scrollableDialog(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              const Text(
                "Client Account Activation",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "VitaLink client accounts require an activation code before registration. This code may come from your insurance agent or from myvitalink.app.\n\n"
                "Do you already have a VitaLink activation code?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              _dialogActionButton(
                label: "I Have a Code",
                primary: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _continueClientRegistration();
                },
              ),
              const SizedBox(height: 10),
              _dialogActionButton(
                label: "Get Activation Code",
                primary: false,
                onPressed: () {
                  Navigator.pop(ctx);
                  _openClientActivationPage();
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAgentActivationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: _scrollableDialog(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              const Text(
                "Agent Portal Activation",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Insurance agent accounts are activated through the VitaLink website before app access is enabled.\n\n"
                "Do you have your activation code?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              _dialogActionButton(
                label: "I Have My Activation Code",
                primary: false,
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(
                    context,
                    '/terms_agent',
                    arguments: {"code": activationCode},
                  );
                },
              ),
              const SizedBox(height: 10),
              _dialogActionButton(
                label: "I Need An Activation Code",
                primary: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _openVitaLinkWebsite();
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeight = constraints.maxHeight < 760;
          final titleSize = compactHeight ? 36.0 : 44.0;
          final logoWidth = compactHeight ? 200.0 : 240.0;
          final topGap = compactHeight ? 26.0 : 60.0;
          final logoGap = compactHeight ? 18.0 : 30.0;
          final buttonGap = compactHeight ? 32.0 : 70.0;
          final bottomImageHeight =
              (constraints.maxHeight * (compactHeight ? 0.18 : 0.24))
                  .clamp(110.0, 210.0);

          return Container(
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
                              SizedBox(height: topGap),

                              Text(
                                "Welcome To",
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                  color: vitalinkBlue,
                                ),
                              ),

                              SizedBox(height: logoGap),

                              Image.asset(
                                'assets/images/vitalink-logo-2.png',
                                width: logoWidth,
                              ),

                              SizedBox(height: buttonGap),

                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  minimumSize: const Size(double.infinity, 55),
                                ),
                                onPressed: _showLoginPopup,
                                child: const Text(
                                  "Log In to Your Account",
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.black,
                                  ),
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
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.black,
                                  ),
                                ),
                              ),

                              SizedBox(height: compactHeight ? 28 : 60),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(
                    width: double.infinity,
                    height: bottomImageHeight,
                    child: Image.asset(
                      'assets/images/landing-bottom.png',
                      width: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
