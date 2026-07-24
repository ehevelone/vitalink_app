// lib/screens/request_reset_screen.dart
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';

class RequestResetScreen extends StatefulWidget {
  const RequestResetScreen({super.key});

  @override
  State<RequestResetScreen> createState() => _RequestResetScreenState();
}

class _RequestResetScreenState extends State<RequestResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _loading = false;

  Future<void> _doRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final data = await ApiService.requestPasswordReset(
        emailOrPhone: _emailCtrl.text.trim(),
        role: "users",
      );

      if (data['success'] == true) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).resetCodeSent)),
        );

        Navigator.pushNamed(
          context,
          '/reset_password',
          arguments: _emailCtrl.text.trim(),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['error'] ?? AppStrings.of(context).requestFailed,
            ),
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
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.requestPasswordReset)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(labelText: strings.emailOrPhone),
                validator: (v) =>
                    v == null || v.isEmpty ? strings.enterEmailOrPhone : null,
              ),
              const SizedBox(height: 24),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text(strings.sendResetCode),
                      onPressed: _doRequest,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
