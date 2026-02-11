// lib/screens/profile_agent_screen.dart
import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../widgets/password_rules.dart';

class ProfileAgentScreen extends StatefulWidget {
  const ProfileAgentScreen({super.key});

  @override
  State<ProfileAgentScreen> createState() => _ProfileAgentScreenState();
}

class _ProfileAgentScreenState extends State<ProfileAgentScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _agencyNameCtrl = TextEditingController();
  final _agencyAddressCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
  }

  Future<void> _loadLocalProfile() async {
    final store = SecureStore();

    _nameCtrl.text = await store.getString('agentName') ?? '';
    _emailCtrl.text = await store.getString('agentEmail') ?? '';
    _phoneCtrl.text = await store.getString('agentPhone') ?? '';
    _agencyNameCtrl.text =
        await store.getString('agencyName') ??
        await store.getString('agentAgency') ??
        '';
    _agencyAddressCtrl.text =
        await store.getString('agencyAddress') ?? '';
  }

  String? _validatePassword(String? pw) {
    if (pw == null || pw.isEmpty) return null;
    if (pw.length < 10) return "≥ 10 characters";
    if (!RegExp(r'[A-Z]').hasMatch(pw)) return "1 uppercase required";
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(pw)) {
      return "1 special character required";
    }
    return null;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final store = SecureStore();

    try {
      final res = await ApiService.updateAgentProfile(
        email: _emailCtrl.text.trim(), // immutable identifier
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        agencyName: _agencyNameCtrl.text.trim().isNotEmpty
            ? _agencyNameCtrl.text.trim()
            : null,
        agencyAddress: _agencyAddressCtrl.text.trim().isNotEmpty
            ? _agencyAddressCtrl.text.trim()
            : null,
        password:
            _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text.trim() : null,
      );

      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'] ?? "Update failed ❌")),
        );
        return;
      }

      // ✅ Sync SecureStore (used by My Agent + HIPAA)
      await store.setString('agentName', _nameCtrl.text.trim());
      await store.setString('agentPhone', _phoneCtrl.text.trim());
      await store.setString('agentEmail', _emailCtrl.text.trim());
      await store.setString('agencyName', _agencyNameCtrl.text.trim());
      await store.setString('agencyAddress', _agencyAddressCtrl.text.trim());

      if (_passwordCtrl.text.isNotEmpty) {
        await store.setString('agentPassword', _passwordCtrl.text.trim());
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Agent profile updated ✅")),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Agent Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Full Name"),
                validator: (v) =>
                    v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _emailCtrl,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: "Email (cannot be changed)",
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: "Phone"),
                validator: (v) =>
                    v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyNameCtrl,
                decoration: const InputDecoration(labelText: "Agency Name"),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyAddressCtrl,
                decoration: const InputDecoration(labelText: "Agency Address"),
                maxLines: 2,
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),

              const Text(
                "Change Password (optional)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "New Password",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: _validatePassword,
              ),
              const SizedBox(height: 8),
              PasswordRules(controller: _passwordCtrl),

              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                decoration: InputDecoration(
                  labelText: "Confirm Password",
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
                    _passwordCtrl.text.isNotEmpty &&
                            v != _passwordCtrl.text
                        ? "Passwords don’t match"
                        : null,
              ),

              const SizedBox(height: 24),
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text("Save Changes"),
                      onPressed: _saveProfile,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
