import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../legal/user_agreement_text.dart';
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
      _p = p;
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
    } else if (context.mounted) {
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
                  const Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        userAgreementText,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                          height: 1.4,
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
