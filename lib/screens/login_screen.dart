import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  bool _rememberMe = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final store = SecureStore();
    final remember = await store.getBool("rememberMeUser") ?? false;
    if (!remember) return;

    final email = await store.getString("savedUserEmail") ?? "";
    final pass = await store.getString("savedUserPassword") ?? "";

    setState(() {
      _rememberMe = true;
      _emailCtrl.text = email;
      _passwordCtrl.text = pass;
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final res = await ApiService.loginUser(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
      platform: "android",
    );

    if (res["success"] == true) {
      final user = res["user"];
      final store = SecureStore();

      await store.remove("agentLoggedIn");
      await store.setBool("userLoggedIn", true);
      await store.setString("role", "user");

      // ✅ cache validated DB values
      await store.setString("userId", user["id"].toString());
      await store.setString("userEmail", user["email"]);
      await store.setString("agent_id", user["agent_id"]?.toString() ?? "");

      if (_rememberMe) {
        await store.setBool("rememberMeUser", true);
        await store.setString("savedUserEmail", _emailCtrl.text.trim());
        await store.setString("savedUserPassword", _passwordCtrl.text.trim());
      } else {
        await store.setBool("rememberMeUser", false);
        await store.remove("savedUserEmail");
        await store.remove("savedUserPassword");
      }

      if (!mounted) return;

      // ✅ ✅ ✅ CRITICAL FIX — ALWAYS GO TO LOGO
      Navigator.pushReplacementNamed(context, "/logo");
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res["error"] ?? "Invalid credentials")),
      );
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("User Login")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: "Email"),
                validator: (v) => v == null || v.isEmpty ? "Enter email" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter password" : null,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                title: const Text("Remember me"),
              ),
              const SizedBox(height: 24),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text("Login"),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
