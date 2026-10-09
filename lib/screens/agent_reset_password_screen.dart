import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/secure_store.dart';

class AgentResetPasswordScreen extends StatefulWidget {
  final String? emailOrPhone;

  const AgentResetPasswordScreen({super.key, this.emailOrPhone});

  @override
  State<AgentResetPasswordScreen> createState() =>
      _AgentResetPasswordScreenState();
}

class _AgentResetPasswordScreenState extends State<AgentResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _showPass = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    if (widget.emailOrPhone != null && widget.emailOrPhone!.isNotEmpty) {
      _emailCtrl.text = widget.emailOrPhone!;
    }
  }

  String? _validatePassword(String? pw) {
    if (pw == null || pw.isEmpty) return AppStrings.of(context).enterAPassword;
    if (pw.length < 10) return AppStrings.of(context).passwordAtLeast10;
    if (!RegExp(r'[A-Z]').hasMatch(pw)) {
      return AppStrings.of(context).passwordNeedsUppercase;
    }
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(pw)) {
      return AppStrings.of(context).passwordNeedsSpecial;
    }
    return null;
  }

  Future<void> _submitNewPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final data = await ApiService.resetPassword(
      emailOrPhone: _emailCtrl.text.trim(),
      code: _codeCtrl.text.trim(),
      newPassword: _newPassCtrl.text.trim(),
      role: "agents",
    );

    if (mounted) setState(() => _loading = false);

    if (data['success'] == true) {
      final store = SecureStore();
      await store.remove('agentLoggedIn');
      await store.remove('role');
      await store.remove('loggedIn');

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppStrings.of(context).success),
          content: Text(AppStrings.of(context).agentPasswordReset),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, '/agent_login');
    } else {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(data['error'] ?? AppStrings.of(context).resetFailed)),
      );
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context).agentResetPassword),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                AppStrings.of(context).agentPortalTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).agentEmail,
                  border: InputBorder.none,
                ),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterEmailAddress
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).sixDigitResetCode,
                  border: InputBorder.none,
                ),
                validator: (v) => v == null || v.length != 6
                    ? AppStrings.of(context).enterValidSixDigitCode
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPassCtrl,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).newPassword,
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPass ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
                validator: _validatePassword,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).confirmPassword,
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirm ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                ),
                validator: (v) => v != _newPassCtrl.text
                    ? AppStrings.of(context).passwordsDoNotMatch
                    : null,
              ),
              const SizedBox(height: 24),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.lock_reset),
                      label: Text(AppStrings.of(context).resetPassword),
                      onPressed: _submitNewPassword,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
