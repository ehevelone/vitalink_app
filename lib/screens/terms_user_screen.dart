import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map) {
      _args = args;
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
      arguments: _args, // 🔥 forward activation code
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
                  const Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        "Welcome to VitaLink (User).\n\n"

                        "By using this app, you agree:\n"
                        "• This app is provided as-is, without warranties.\n"
                        "• You are responsible for the accuracy of your data.\n"
                        "• This app does not replace professional medical advice.\n"
                        "• Always consult licensed healthcare providers for medical decisions.\n\n"

                        "Activation Requirement\n\n"
                        "A VitaLink account requires an activation code.\n\n"

                        "Clients of participating insurance agents will receive an activation code from their agent.\n\n"

                        "Personal users can obtain an activation code at:\n"
                        "myvitalink.app\n\n"

                        "If you do not agree to these terms, you cannot use the app.",
                        style: TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(
                        onPressed: () => _handleDecline(context),
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