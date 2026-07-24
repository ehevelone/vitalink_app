import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? emailOrPhone;

  const ResetPasswordScreen({super.key, this.emailOrPhone});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _showPass = false;
  bool _showConfirm = false;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    if (widget.emailOrPhone != null && widget.emailOrPhone!.isNotEmpty) {
      _emailCtrl.text = widget.emailOrPhone!;
    }
  }

  String? _validatePassword(String? pw) {
    final strings = AppStrings.of(context);
    if (pw == null || pw.isEmpty) return strings.enterAPassword;
    if (pw.length < 10) return strings.passwordAtLeast10;
    if (!RegExp(r'[A-Z]').hasMatch(pw)) {
      return strings.passwordNeedsUppercase;
    }
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(pw)) {
      return strings.passwordNeedsSpecial;
    }
    return null;
  }

  Future<void> _sendResetCode() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).enterEmailFirst)),
      );
      return;
    }

    setState(() => _loading = true);

    final data = await ApiService.requestPasswordReset(
      emailOrPhone: _emailCtrl.text.trim(),
      role: "users",
    );

    if (mounted) setState(() => _loading = false);
    if (!mounted) return;

    if (data['success'] == true) {
      setState(() => _codeSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context)
              .resetCodeSentTo('${data['sentTo'] ?? _emailCtrl.text}')),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                data['error'] ?? AppStrings.of(context).failedToSendResetCode)),
      );
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final data = await ApiService.resetPassword(
      emailOrPhone: _emailCtrl.text.trim(),
      code: _codeCtrl.text.trim(),
      newPassword: _newPassCtrl.text.trim(),
      role: "users",
    );

    if (mounted) setState(() => _loading = false);
    if (!mounted) return;

    if (data['success'] == true) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppStrings.of(context).success),
          content: Text(AppStrings.of(context).passwordResetSuccess),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).ok),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } else {
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
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.resetPassword)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (!_codeSent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    strings.resetStepOne,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                  labelText: strings.emailAddress,
                  border: InputBorder.none,
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? strings.enterEmailAddress : null,
              ),
              const SizedBox(height: 12),
              if (_codeSent) ...[
                TextFormField(
                  controller: _codeCtrl,
                  decoration: InputDecoration(
                    labelText: strings.sixDigitResetCode,
                    border: InputBorder.none,
                  ),
                  validator: (v) => v == null || v.length != 6
                      ? strings.enterValidSixDigitCode
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPassCtrl,
                  obscureText: !_showPass,
                  decoration: InputDecoration(
                    labelText: strings.newPassword,
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _showPass ? Icons.visibility_off : Icons.visibility),
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
                    labelText: strings.confirmPassword,
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: Icon(_showConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _showConfirm = !_showConfirm),
                    ),
                  ),
                  validator: (v) => v != _newPassCtrl.text
                      ? strings.passwordsDoNotMatch
                      : null,
                ),
              ],
              const SizedBox(height: 24),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: Icon(
                          _codeSent ? Icons.lock_reset : Icons.mark_email_read),
                      label: Text(_codeSent
                          ? strings.resetPassword
                          : strings.sendResetCode),
                      onPressed:
                          _codeSent ? _submitNewPassword : _sendResetCode,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
