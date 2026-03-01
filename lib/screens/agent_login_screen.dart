import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';

class AgentLoginScreen extends StatefulWidget {
  const AgentLoginScreen({super.key});

  @override
  State<AgentLoginScreen> createState() => _AgentLoginScreenState();
}

class _AgentLoginScreenState extends State<AgentLoginScreen> {
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
    final remember = await store.getBool("rememberMeAgent") ?? false;
    final email = await store.getString("savedAgentEmail") ?? "";
    final pass = await store.getString("savedAgentPassword") ?? "";

    if (!mounted) return;

    if (remember) {
      setState(() {
        _rememberMe = true;
        _emailCtrl.text = email;
        _passwordCtrl.text = pass;
      });
    }
  }

  Future<void> _login() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _loading = true);

    try {
      final email = _emailCtrl.text.trim();

      final res = await ApiService.loginAgent(
        email: email,
        password: _passwordCtrl.text.trim(),
      );

      if (!mounted) return;

      if (res["success"] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(res["error"]?.toString() ?? "Invalid credentials")),
        );
        setState(() => _loading = false);
        return;
      }

      final agent = res["agent"];

      if (agent == null ||
          agent["email"] == null ||
          agent["id"] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Invalid agent response from server")),
        );
        setState(() => _loading = false);
        return;
      }

      final store = SecureStore();

      await AppState.clearAuth();
      await AppState.setLoggedIn(true);
      await AppState.setRole("agent");
      await AppState.setEmail(agent["email"].toString());

      await store.setString(
          "agentId", agent["id"].toString());
      await store.setString(
          "agentEmail", agent["email"]?.toString() ?? "");
      await store.setString(
          "agentName", agent["name"]?.toString() ?? "");
      await store.setString(
          "agentPhone", agent["phone"]?.toString() ?? "");

      if (_rememberMe) {
        await store.setBool("rememberMeAgent", true);
        await store.setString("savedAgentEmail", email);
        await store.setString(
            "savedAgentPassword", _passwordCtrl.text.trim());
      } else {
        await store.setBool("rememberMeAgent", false);
        await store.remove("savedAgentEmail");
        await store.remove("savedAgentPassword");
      }

      try {
        final fcm =
            await FirebaseMessaging.instance.getToken();
        if (fcm != null) {
          await ApiService.registerDeviceToken(
            email: agent["email"].toString(),
            fcmToken: fcm,
            role: "agent",
          );
        }
      } catch (_) {}

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, "/logo");
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login error: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToReset() {
    Navigator.pushNamed(context, "/agent_request_reset");
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Agent Login")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration:
                    const InputDecoration(labelText: "Agent Email"),
                validator: (v) =>
                    v == null || v.isEmpty
                        ? "Enter your email"
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() =>
                            _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty
                        ? "Enter password"
                        : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _goToReset,
                  child: const Text("Forgot Password?"),
                ),
              ),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (v) =>
                    setState(() => _rememberMe = v ?? false),
                title: const Text("Remember me"),
                controlAffinity:
                    ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 24),
              _loading
                  ? const Center(
                      child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text("Login as Agent"),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}