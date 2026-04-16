import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; // ✅ ADDED
import 'package:url_launcher/url_launcher.dart'; // ✅ REQUIRED

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class TermsAgentScreen extends StatefulWidget {
  const TermsAgentScreen({super.key});

  @override
  State<TermsAgentScreen> createState() => _TermsAgentScreenState();
}

class _TermsAgentScreenState extends State<TermsAgentScreen> {
  late final DataRepository _repo;
  Profile? _p;

  String? activationCode;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
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
  }

  Future<void> _load() async {
    final p = await _repo.loadProfile();
    if (!mounted) return;

    setState(() {
      _p = p ?? Profile();
    });
  }

  Future<void> _handleAccept() async {
    if (_p == null) return;

    _p!
      ..acceptedTerms = true
      ..updatedAt = DateTime.now();

    await _repo.saveProfile(_p!);
    await SecureStore().setBool('agentTerms', true);

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      '/agent_registration',
      arguments: {"code": activationCode},
    );
  }

  void _handleDecline(BuildContext context) async {
    final uninstall = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Decline Terms"),
        content: const Text(
          "If you do not accept the terms, you cannot use VitaLink (Agent).",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Exit App"),
          ),
        ],
      ),
    );

    if (uninstall == true) {
      SystemNavigator.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must accept the terms to continue.")),
      );
    }
  }

  Future<void> _handleBack() async {
    await SecureStore().remove('role');

    if (!mounted) return;

    Navigator.pushReplacementNamed(context, '/landing');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Agent Terms of Service"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/logo_icon.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 16, color: Colors.black),
                          children: [
                            const TextSpan(
                              text:
                                  "Welcome to VitaLink (Agent).\n\n"

                                  "By using this app as an Agent, you agree:\n"
                                  "• You must maintain a valid license to offer Medicare services.\n"
                                  "• You are solely responsible for compliance with CMS and AHIP guidelines.\n"
                                  "• You must safeguard client data and never share login credentials.\n"
                                  "• You agree that misuse may result in immediate access termination.\n\n"

                                  "Agent Responsibility & Compliance\n\n"
                                  "• You are responsible for ensuring all client information entered or shared is accurate and up to date.\n"
                                  "• You must handle all client data in accordance with applicable privacy, security, and regulatory requirements.\n"
                                  "• VitaLink does not verify or validate any data entered by agents or users.\n\n"

                                  "Medical & Liability Disclaimer\n\n"
                                  "• VitaLink is a data storage and sharing tool only and does not verify, validate, or guarantee the accuracy, completeness, or timeliness of any information.\n"
                                  "• VitaLink is not a medical provider, insurer, or licensed advisory service.\n"
                                  "• The app does not provide medical advice, diagnosis, or treatment recommendations.\n"
                                  "• Agents and users must not rely solely on this app for healthcare or emergency decisions.\n"
                                  "• VitaLink is not liable for errors, omissions, or outdated information contained within the app.\n\n"

                                  "Activation & Client Access\n\n"
                                  "Agents may provide activation codes to their clients for access to the VitaLink service.\n\n"

                                  "Clients of participating agents will receive an activation code from their agent.\n\n"

                                  "Agents are responsible for ensuring that any client information entered into the app is accurate and handled in accordance with applicable privacy and regulatory requirements.\n\n"

                                  "For full Terms of Service and Privacy Policy, visit:\n",
                            ),

                            TextSpan(
                              text:
                                  "https://myvitalink.app/terms\n\n",
                              style: const TextStyle(
                                color: Colors.blue,
                                decoration:
                                    TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () async {
                                  final uri = Uri.parse(
                                      "https://myvitalink.app/terms");
                                  await launchUrl(uri,
                                      mode: LaunchMode
                                          .externalApplication);
                                },
                            ),

                            const TextSpan(
                              text:
                                  "If you do not agree to these terms, you cannot use the app as an Agent.",
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(
                        onPressed: () =>
                            _handleDecline(context),
                        child: const Text("Decline"),
                      ),
                      ElevatedButton(
                        onPressed: _handleAccept,
                        child: const Text("Accept"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}