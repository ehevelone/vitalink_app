import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const Color vitalinkBlue = Color(0xFF79CAE3);
  static const Color panelDark = Color(0xFF1A1A1A);
  static const Color cardDark = Color(0xFF101010);

  Widget _scrollableDialog(BuildContext context, {required Widget child}) {
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

  void _showLoginOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).logInAs),
        content: Text(AppStrings.of(context).chooseAccountType),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/login'); // User login
            },
            child: Text(AppStrings.of(context).userLogin),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/agent_login');
            },
            child: Text(AppStrings.of(context).agentLogin),
          ),
        ],
      ),
    );
  }

  void _showRegisterOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: _scrollableDialog(
          context,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.of(context).createAccount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.of(context).chooseAccountType,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                _registerOption(
                  context,
                  icon: Icons.family_restroom,
                  title: AppStrings.of(context).createClientAccount,
                  subtitle: AppStrings.of(context).forUsersAndFamilies,
                  color: Colors.green,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showClientActivationDialog(context);
                  },
                ),
                const SizedBox(height: 12),
                _registerOption(
                  context,
                  icon: Icons.business_center,
                  title: AppStrings.of(context).activateAgentPortal,
                  subtitle: AppStrings.of(context).agentActivationSubtitle,
                  color: vitalinkBlue,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAgentActivationDialog(context);
                  },
                ),
              ],
            ),
          ),
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
          color: cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.black, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
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

  void _showClientActivationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: _scrollableDialog(
          context,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.of(context).clientAccountActivation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppStrings.of(context).activationCodeIntro(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                _dialogActionButton(
                  label: AppStrings.of(context).iHaveCode,
                  primary: true,
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/registration');
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(AppStrings.of(context).cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAgentActivationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: _scrollableDialog(
          context,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.of(context).agentPortalActivation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppStrings.of(context).agentActivationBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                _dialogActionButton(
                  label: AppStrings.of(context).continueWithRegistrationCode,
                  primary: true,
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/terms_agent');
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(AppStrings.of(context).cancel),
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
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppStrings.of(context).welcomeToVitalink,
              style: const TextStyle(
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
              child: Text(
                AppStrings.of(context).loginToYourAccount,
                style: const TextStyle(fontSize: 18),
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
              child: Text(
                AppStrings.of(context).registerForAccount,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
