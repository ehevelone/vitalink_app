import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import 'package:url_launcher/url_launcher.dart';

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

  String? _errorMessage;

  // 🔥 Overlay (popup)
  bool _showAccessOverlay = false;
  String _overlayMessage = "";

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

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

// 🔥 NEW: clean close handler
void _closeOverlay() {
  setState(() {
    _showAccessOverlay = false;
  });
}

Future<void> _openActivationPage() async {
  final url = Uri.parse("https://myvitalink.app/agent-portal-activation");

  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Could not open activation page")),
    );
  }
}

Future<String?> _chooseBillingInterval() {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Choose Billing"),
      content: const Text("How would you like to activate your VitaLink Agent Access?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop("monthly"),
          child: const Text("Monthly"),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop("annual"),
          child: const Text("Annual"),
        ),
      ],
    ),
  );
}

Future<void> _login() async {
  final form = _formKey.currentState;
  if (form == null || !form.validate()) return;

  setState(() {
    _loading = true;
    _errorMessage = null;
  });

  try {
    final res = await ApiService.loginAgent(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
    );

    if (!mounted) return;

    if (res["success"] != true) {
      setState(() {
        _loading = false;
      });

      if (res["requires_payment"] == true && res["agentId"] != null) {
        final billing = await _chooseBillingInterval();
        if (billing == null) {
          if (mounted) setState(() => _loading = false);
          return;
        }

        final checkout = await ApiService.createAgentCheckout(
          email: res["email"]?.toString() ?? _emailCtrl.text.trim(),
          agentId: res["agentId"]?.toString(),
          plan: "agent",
          billing: billing,
        );

        if (!mounted) return;

        final checkoutUrl = checkout["url"]?.toString() ?? "";
        if (checkoutUrl.isNotEmpty) {
          setState(() => _loading = false);
          await launchUrl(
            Uri.parse(checkoutUrl),
            mode: LaunchMode.externalApplication,
          );
          return;
        }
      }

      // Show the access activation prompt when backend access is not active.
      if (res["requires_payment"] == true) {
        setState(() {
          _showAccessOverlay = true;
          _overlayMessage =
              "Your agent portal access is not active.\n\nVisit myvitalink.app to activate access before logging in.";
        });
        return;
      }

      // ❌ Normal error
      setState(() {
        _errorMessage = res["error"] ?? "Login failed";
      });

      return;
    }

    final agent = res["agent"];

    if (agent == null) {
      setState(() {
        _errorMessage = "Invalid response";
        _loading = false;
      });
      return;
    }

      final store = SecureStore();

      await AppState.clearAuth();
      await AppState.setLoggedIn(true);
      await AppState.setRole("agent");

      await store.setString("agentId", agent["id"].toString());
      await store.setString("agentEmail", agent["email"] ?? "");
      await store.setString("agentName", agent["name"] ?? "");

      final sessionToken = res["token"]?.toString() ?? "";
      if (sessionToken.isNotEmpty) {
        await store.setString("agentSessionToken", sessionToken);
      } else {
        await store.remove("agentSessionToken");
      }

      if (_rememberMe) {
        await store.setBool("rememberMeAgent", true);
        await store.setString("savedAgentEmail", _emailCtrl.text.trim());
        await store.setString("savedAgentPassword", _passwordCtrl.text.trim());
      } else {
        await store.setBool("rememberMeAgent", false);
        await store.remove("savedAgentEmail");
        await store.remove("savedAgentPassword");
      }

      try {
        final fcm = await FirebaseMessaging.instance.getToken();
        if (fcm != null) {
          final agentId = int.tryParse(agent["id"].toString());
          if (agentId != null && agentId > 0) {
            await ApiService.registerAgentDeviceToken(
              agentId: agentId,
              fcmToken: fcm,
            );
          }
        }
      } catch (e) {
        debugPrint("Agent device registration failed: $e");
      }

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, "/logo");
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = "Login error";
        _loading = false;
      });
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
      body: Stack(
        children: [

          // 🔹 MAIN UI
          Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [

                  TextFormField(
                    controller: _emailCtrl,
                    onChanged: (_) => _clearError(),
                    decoration: const InputDecoration(labelText: "Agent Email"),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter your email" : null,
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _passwordCtrl,
                    onChanged: (_) => _clearError(),
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
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter password" : null,
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],

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
                  ),

                  const SizedBox(height: 24),

                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _login,
                          child: const Text("Login as Agent"),
                        ),
                ],
              ),
            ),
          ),

          // 🔥 FINAL POPUP OVERLAY
          if (_showAccessOverlay)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF79CAE3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 12,
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [

                        const Text(
                          "Access Not Active",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          _overlayMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.35,
                          ),
                        ),

                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF79CAE3),
                                  side: const BorderSide(
                                    color: Color(0xFF79CAE3),
                                  ),
                                ),
                                onPressed: _closeOverlay,
                                child: const Text("Contact Agency"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF79CAE3),
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () {
                                  _closeOverlay();
                                  _openActivationPage();
                                },
                                child: const Text("Continue"),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
