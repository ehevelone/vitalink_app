import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _showLoginOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Log In As"),
        content: const Text("Please choose your account type."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/login'); // User login
            },
            child: const Text("User Login"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/agent_login');
            },
            child: const Text("Agent Login"),
          ),
        ],
      ),
    );
  }

  void _showRegisterOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Choose the account type that matches how you use VitaLink."),
            const SizedBox(height: 16),
            _registerOption(
              context,
              icon: Icons.family_restroom,
              title: "Create Client Account",
              subtitle: "For VitaLink users and families",
              color: Colors.green,
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/registration');
              },
            ),
            const SizedBox(height: 12),
            _registerOption(
              context,
              icon: Icons.business_center,
              title: "Activate Agent Portal",
              subtitle:
                  "Insurance agents must activate access through myvitalink.app",
              color: Colors.blue,
              onPressed: () {
                Navigator.pop(ctx);
                _showAgentActivationDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _registerOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontSize: 13,
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

  void _showAgentActivationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Agent Portal Activation"),
        content: const Text(
          "Insurance agent accounts are activated through the VitaLink website before app access is enabled.\n\n"
          "Have you already activated your agent account through myvitalink.app?",
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
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Welcome to VitaLink",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),

            // GREEN LOGIN BUTTON
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 55),
              ),
              onPressed: () => _showLoginOptions(context),
              child: const Text(
                "Log In to Your Account",
                style: TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 20),

            // BLUE REGISTER BUTTON
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 55),
              ),
              onPressed: () => _showRegisterOptions(context),
              child: const Text(
                "Register for an Account",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
