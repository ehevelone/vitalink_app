// lib/screens/agent_request_reset_screen.dart
import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';

class AgentRequestResetScreen extends StatefulWidget {
  const AgentRequestResetScreen({super.key});

  @override
  State<AgentRequestResetScreen> createState() =>
      _AgentRequestResetScreenState();
}

class _AgentRequestResetScreenState extends State<AgentRequestResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _loading = false;

  Future<void> _doRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final data = await ApiService.requestPasswordReset(
        emailOrPhone: _emailCtrl.text.trim(),
        role: "agents", // 🔥 REQUIRED
      );

      if (data['success'] == true) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppStrings.of(context).resetCodeSentCheckShort)),
        );

        Navigator.pushNamed(
          context,
          '/agent_reset_password',
          arguments: _emailCtrl.text.trim(),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(data['error'] ?? AppStrings.of(context).requestFailedX),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).errorMessage('$e'))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).agentRequestReset)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agentEmail),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterYourEmail
                    : null,
              ),
              const SizedBox(height: 24),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text(AppStrings.of(context).sendResetCode),
                      onPressed: _doRequest,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
