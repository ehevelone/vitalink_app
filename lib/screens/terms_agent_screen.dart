import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
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
      _p = p;
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
        title: Text(AppStrings.of(context).declineTerms),
        content: Text(
          AppStrings.of(context).declineAgentTermsBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.of(context).no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.of(context).exitApp),
          ),
        ],
      ),
    );

    if (uninstall == true) {
      SystemNavigator.pop();
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).mustAcceptTerms)),
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
        title: Text(AppStrings.of(context).agentTermsOfService),
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
              cacheWidth: (MediaQuery.of(context).size.width *
                      MediaQuery.of(context).devicePixelRatio)
                  .round(),
              cacheHeight: (MediaQuery.of(context).size.height *
                      MediaQuery.of(context).devicePixelRatio)
                  .round(),
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
                            TextSpan(
                              text: AppStrings.of(context).agentTermsBody(),
                            ),
                            TextSpan(
                              text: "https://myvitalink.app/terms\n\n",
                              style: const TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () async {
                                  final uri =
                                      Uri.parse("https://myvitalink.app/terms");
                                  await launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                },
                            ),
                            TextSpan(
                              text: AppStrings.of(context).agentTermsClosing,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(
                        onPressed: () => _handleDecline(context),
                        child: Text(AppStrings.of(context).decline),
                      ),
                      ElevatedButton(
                        onPressed: _handleAccept,
                        child: Text(AppStrings.of(context).accept),
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
