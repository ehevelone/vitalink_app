// lib/screens/agent_request_reset_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AgentRequestResetScreen extends StatefulWidget {
  const AgentRequestResetScreen({super.key});

  @override
  State<AgentRequestResetScreen> createState() =>
      _AgentRequestResetScreenState();
}

class _AgentRequestResetScreenState
    extends State<AgentRequestResetScreen> {
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
          const SnackBar(content: Text("Reset code sent ✅")),
        );

        Navigator.pushNamed(
          context,
          '/agent_reset_password',
          arguments: _emailCtrl.text.trim(),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(data['error'] ?? "Request failed ❌"),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
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
      appBar:
          AppBar(title: const Text("Agent Request Reset")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                    labelText: "Agent Email"),
                validator: (v) =>
                    v == null || v.isEmpty
                        ? "Enter your email"
                        : null,
              ),
              const SizedBox(height: 24),
              _loading
                  ? const Center(
                      child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label:
                          const Text("Send Reset Code"),
                      onPressed: _doRequest,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}