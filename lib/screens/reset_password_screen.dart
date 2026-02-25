// lib/screens/reset_password_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? emailOrPhone;

  const ResetPasswordScreen({super.key, this.emailOrPhone});

  @override
  State<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState
    extends State<ResetPasswordScreen> {
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
    if (widget.emailOrPhone != null &&
        widget.emailOrPhone!.isNotEmpty) {
      _emailCtrl.text = widget.emailOrPhone!;
    }
  }

  String? _validatePassword(String? pw) {
    if (pw == null || pw.isEmpty) return "Enter a password";
    if (pw.length < 10) return "Must be at least 10 characters";
    if (!RegExp(r'[A-Z]').hasMatch(pw)) {
      return "Must contain at least one uppercase letter";
    }
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(pw)) {
      return "Must contain at least one special character";
    }
    return null;
  }

  Future<void> _sendResetCode() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter your email address first")),
      );
      return;
    }

    setState(() => _loading = true);

    final data = await ApiService.requestPasswordReset(
      emailOrPhone: _emailCtrl.text.trim(),
      role: "users", // 🔥 REQUIRED
    );

    if (data['success'] == true) {
      setState(() => _codeSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Reset code sent to ${data['sentTo'] ?? _emailCtrl.text} (expires in 20 minutes)",
          ),
        ),
      );
    } else {
      setState(() => _codeSent = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['error'] ?? "Failed to send reset code"),
        ),
      );
    }

    if (mounted) setState(() => _loading = false);
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

    if (data['success'] == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password reset successful")),
      );
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['error'] ?? "Reset failed")),
      );
    }

    if (mounted) setState(() => _loading = false);
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
      appBar: AppBar(title: const Text("Reset Password")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (!_codeSent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Step 1: We'll email you a 6-digit reset code.",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),

              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: "Email Address",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty
                        ? "Enter your email address"
                        : null,
              ),
              const SizedBox(height: 12),

              if (_codeSent) ...[
                TextFormField(
                  controller: _codeCtrl,
                  decoration: const InputDecoration(
                    labelText: "6-digit Reset Code",
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.length != 6
                          ? "Enter valid 6-digit code"
                          : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _newPassCtrl,
                  obscureText: !_showPass,
                  decoration: InputDecoration(
                    labelText: "New Password",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPass
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _showPass = !_showPass),
                    ),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: !_showConfirm,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setState(
                          () => _showConfirm = !_showConfirm),
                    ),
                  ),
                  validator: (v) =>
                      v != _newPassCtrl.text
                          ? "Passwords do not match"
                          : null,
                ),
              ],

              const SizedBox(height: 24),

              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: Icon(
                        _codeSent
                            ? Icons.lock_reset
                            : Icons.mark_email_read,
                      ),
                      label: Text(
                        _codeSent
                            ? "Reset Password"
                            : "Send Reset Code",
                      ),
                      onPressed:
                          _codeSent
                              ? _submitNewPassword
                              : _sendResetCode,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}