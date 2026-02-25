import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/secure_store.dart';

class AgentResetPasswordScreen extends StatefulWidget {
  final String? emailOrPhone;

  const AgentResetPasswordScreen({super.key, this.emailOrPhone});

  @override
  State<AgentResetPasswordScreen> createState() =>
      _AgentResetPasswordScreenState();
}

class _AgentResetPasswordScreenState
    extends State<AgentResetPasswordScreen> {
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
          title: const Text("Success"),
          content: const Text(
              "Agent password has been reset successfully."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );

      Navigator.pushReplacementNamed(context, '/agent_login');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['error'] ?? "Reset failed")),
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
        title: const Text("Agent Reset Password"),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                "VitaLink Agent Portal",
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: "Agent Email",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty
                        ? "Enter your email address"
                        : null,
              ),
              const SizedBox(height: 12),

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
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                ),
                validator: (v) =>
                    v != _newPassCtrl.text
                        ? "Passwords do not match"
                        : null,
              ),
              const SizedBox(height: 24),

              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.lock_reset),
                      label: const Text("Reset Password"),
                      onPressed: _submitNewPassword,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}