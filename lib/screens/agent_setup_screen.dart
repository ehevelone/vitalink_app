import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import '../utils/phone_formatter.dart'; // ✅ ADDED

class AgentSetupScreen extends StatefulWidget {
  const AgentSetupScreen({super.key});

  @override
  State<AgentSetupScreen> createState() => _AgentSetupScreenState();
}

class _AgentSetupScreenState extends State<AgentSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _agencyCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = SecureStore();
    _nameCtrl.text = await store.getString('agentName') ?? '';
    _phoneCtrl.text = await store.getString('agentPhone') ?? '';
    _agencyCtrl.text = await store.getString('agencyName') ?? '';
    _licenseCtrl.text = await store.getString('agentId') ?? '';
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final store = SecureStore();
    await store.setBool('agentSetupDone', true);
    await store.setString('role', 'agent');
    await store.setString('agentName', _nameCtrl.text.trim());
    await store.setString('agentPhone', _phoneCtrl.text.trim());
    await store.setString('agencyName', _agencyCtrl.text.trim());
    await store.setString('agencyAddress', "");
    await store.setString('agentId', _licenseCtrl.text.trim());

    if (_passwordCtrl.text.isNotEmpty) {
      await store.setString('agentPassword', _passwordCtrl.text.trim());
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/agent_menu');
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Agent Setup")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: "Full Name"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Enter your name" : null,
                ),
                const SizedBox(height: 12),

                // ✅ FIXED PHONE FIELD
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    PhoneNumberFormatter(),
                  ],
                  decoration: const InputDecoration(labelText: "Phone"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Enter your phone" : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _agencyCtrl,
                  decoration: const InputDecoration(labelText: "Agency"),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _licenseCtrl,
                  decoration: const InputDecoration(labelText: "NPN / License #"),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Enter your NPN" : null,
                ),
                const SizedBox(height: 24),

                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  "Update Password (optional)",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "New Password"),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: "Confirm Password"),
                  validator: (v) {
                    if (_passwordCtrl.text.isNotEmpty &&
                        v != _passwordCtrl.text) {
                      return "Passwords don’t match";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _save,
                        child: const Text("Finish Setup"),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}