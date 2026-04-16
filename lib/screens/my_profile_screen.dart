// lib/screens/my_profile.dart
import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../models.dart';
import '../utils/phone_formatter.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _agencyNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _npnCtrl = TextEditingController();

  bool _loading = true;
  String _role = "user";
  String _email = "";
  Profile? _active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = SecureStore();
    _role = await store.getString("role") ?? "user";

    if (_role == "user") {
      final repo = DataRepository(store);
      _active = await repo.loadProfile();
      if (_active != null) {
        _nameCtrl.text = _active!.fullName;
        _phoneCtrl.text = _active!.emergency.phone;
      }
    } else {
      _email = await store.getString("agentEmail") ?? "";
      _nameCtrl.text = await store.getString("agentName") ?? "";
      _phoneCtrl.text = await store.getString("agentPhone") ?? "";
      _agencyNameCtrl.text = await store.getString("agencyName") ?? "";
      _addressCtrl.text = await store.getString("agencyAddress") ?? "";
      _npnCtrl.text = await store.getString("agentId") ?? "";
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final store = SecureStore();

    if (_role == "user") {
      final repo = DataRepository(store);
      final p = await repo.loadProfile();
      if (p != null) {
        p.fullName = _nameCtrl.text.trim();
        p.emergency.phone = _phoneCtrl.text.trim();
        p.updatedAt = DateTime.now();
        await repo.saveProfile(p);
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Profile updated")));
        Navigator.pop(context, true);
      }
    } else {
      final result = await ApiService.updateAgentProfile(
        email: _email.trim(),
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        agencyName: _agencyNameCtrl.text.trim(),
        agencyAddress: _addressCtrl.text.trim(),
        password: _passwordCtrl.text.trim().isEmpty
            ? null
            : _passwordCtrl.text.trim(),
      );

      if (result['success'] == true) {
        await store.setString("agentName", _nameCtrl.text.trim());
        await store.setString("agentPhone", _phoneCtrl.text.trim());
        await store.setString("agencyName", _agencyNameCtrl.text.trim());
        await store.setString("agencyAddress", _addressCtrl.text.trim());

        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("Profile updated")));
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? "Update error")),
          );
        }
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (_role == "agent" && _email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    "Email: $_email",
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Full Name"),
                validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: "Phone"),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
                validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
              ),

              if (_role == "agent") ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _agencyNameCtrl,
                  decoration: const InputDecoration(labelText: "Agency Name"),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressCtrl,
                  decoration:
                      const InputDecoration(labelText: "Agency Address"),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _npnCtrl,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: "NPN (not editable)",
                  ),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: "New Password (optional)"),
                ),
              ],

              const SizedBox(height: 28),

              // 🔥 FIXED BUTTON
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Save Changes",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}