import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; // ✅ ADDED

import 'package:url_launcher/url_launcher.dart'; // ✅ REQUIRED

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class TermsUserScreen extends StatefulWidget {
  const TermsUserScreen({super.key});

  @override
  State<TermsUserScreen> createState() => _TermsUserScreenState();
}

class _TermsUserScreenState extends State<TermsUserScreen> {
  late final DataRepository _repo;
  Profile? _p;

  Map? _args;

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

      if (args is Map && _args == null) {
        _args = args;
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
    await SecureStore().setBool('userTerms', true);

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      '/registration',
      arguments: _args,
    );
  }

  void _handleDecline(BuildContext context) async {
    final uninstall = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Decline Terms"),
        content: const Text(
          "If you do not accept the terms, you cannot use VitaLink.",
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
        title: const Text("User Terms of Service"),
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
                                  "Welcome to VitaLink (User).\n\n"

                                  "By using this app, you agree:\n"
                                  "• This app is provided as-is, without warranties.\n"
                                  "• You are responsible for the accuracy and completeness of all data entered.\n\n"

                                  "Medical & Platform Disclaimer\n\n"
                                  "• VitaLink is a data storage and sharing tool only and does not verify, validate, or guarantee the accuracy, completeness, or timeliness of any information.\n"
                                  "• VitaLink is not a medical provider, insurer, or licensed advisory service.\n"
                                  "• This app does not provide medical advice, diagnosis, or treatment.\n"
                                  "• Always consult licensed healthcare providers for medical decisions.\n\n"

                                  "Emergency Disclaimer\n\n"
                                  "• VitaLink is not an emergency service.\n"
                                  "• Information displayed may not be complete, current, or verified.\n"
                                  "• First responders and medical personnel should not rely solely on this app for treatment decisions.\n"
                                  "• In an emergency, call 911 or local emergency services immediately.\n\n"

                                  "Insurance Information\n\n"
                                  "• Insurance cards and documents are user-provided and may not reflect current coverage.\n"
                                  "• You are responsible for ensuring all insurance information is accurate and up to date.\n\n"

                                  "Activation Requirement\n\n"
                                  "A VitaLink account requires an activation code.\n\n"

                                  "Clients of participating insurance agents will receive an activation code from their agent.\n\n"

                                  "Personal users can obtain an activation code at:\n"
                                  "myvitalink.app\n\n"

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
                                  "If you do not agree to these terms, you cannot use the app.",
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