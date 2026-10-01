import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/device_id.dart';
import '../services/device_security_service.dart';
import '../services/device_transfer_service.dart';
import 'reset_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = true;
  bool _rememberMe = false;
  bool _showPassword = false;

  String? _errorMessage;

  Future<void> _restoreTransferAfterLogin() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Load Your VitaLink Profiles'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Transfer code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Load Profiles'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty) return;
    try {
      await DeviceTransferService().redeemTransfer(code);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Transfer Complete'),
          content: const Text(
            'Your VitaLink profiles and locally stored information are now on this device.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Transfer Not Loaded'),
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLogin();
    });
  }

  Future<void> _initLogin() async {
    final store = SecureStore();

    final remember = await store.getBool("rememberMeUser");

    if (remember == true) {
      final email = await store.getString("savedUserEmail") ?? "";
      final pass = await store.getString("savedUserPassword") ?? "";

      _emailCtrl.text = email;
      _passwordCtrl.text = pass;
      _rememberMe = true;
    }

    setState(() {
      _loading = false;
    });
  }

  Future<String?> _showReplacePopup() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "New App Installation Detected",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "VitaLink found another installation for this account.\n\n"
                "If this is the same phone after an update or reinstall, confirm it below. If you are moving to a different phone, use Transfer Profile to New Device first. Account recovery does not restore information stored only on another device.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => Navigator.pop(ctx, "current_installation"),
                child: const Text("This Is My Current Phone",
                    style: TextStyle(color: Colors.black)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => Navigator.pop(ctx, "replaced"),
                child: const Text("I Created a Transfer Code",
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => Navigator.pop(ctx, "lost_stolen"),
                child: const Text("It Was Lost or Stolen",
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login({
    bool replace = false,
    bool auto = false,
    bool recoverInstallation = false,
    String replacementReason = "replaced",
  }) async {
    if (!auto && !_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();
    final deviceId = await DeviceId.getOrCreate();
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    final platform =
        !mounted || Theme.of(context).platform == TargetPlatform.iOS
            ? "ios"
            : "android";

    final res = await ApiService.loginUser(
      email: email,
      password: password,
      platform: platform,
      deviceId: deviceId,
      fcmToken: fcmToken,
      recoverInstallation: recoverInstallation,
      replace: replace,
      replacementReason: replacementReason,
    );

    if (!mounted) return;

    if (res["success"] == true) {
      final user = res["user"];
      final store = SecureStore();
      await DeviceSecurityService.clearLocalRevocationForReplacement();

      await AppState.setLoggedIn(true);
      await AppState.setRole("user");
      await AppState.setEmail(user["email"]);

      // ✅ FIX — STORE AS STRING
      await store.setString("userId", user["id"].toString());

      await store.setString("userEmail", user["email"]);

      final sessionToken = user["session_token"]?.toString() ?? "";
      if (sessionToken.isNotEmpty) {
        await store.setString("userSessionToken", sessionToken);
      } else {
        await store.remove("userSessionToken");
      }

      if (_rememberMe) {
        await store.setBool("rememberMeUser", true);
        await store.setString("savedUserEmail", email);
        await store.setString("savedUserPassword", password);
      } else {
        await store.setBool("rememberMeUser", false);
        await store.remove("savedUserEmail");
        await store.remove("savedUserPassword");
      }

      try {
        final fcm = await FirebaseMessaging.instance.getToken();
        if (fcm != null) {
          final userId = await store.getString("userId");
          if (userId != null) {
            await ApiService.registerDeviceToken(
              userId: userId,
              fcmToken: fcm,
            );
          }
        }
      } catch (_) {}

      if (!mounted) return;

      if (replace && replacementReason == 'replaced') {
        await _restoreTransferAfterLogin();
        if (!mounted) return;
      }
      Navigator.pushReplacementNamed(context, "/logo");
    } else if (res["error"] == "DEVICE_ACTIVE" && replace == false) {
      final choice = await _showReplacePopup();
      if (choice == "lost_stolen") {
        if (!mounted) return;
        final lostOrStolen = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Disable the old device?"),
            content: const Text(
              "The old device will be disabled the next time it connects. Information stored outside VitaLink, including screenshots or exported files, cannot be recalled.",
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel")),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, "lost"),
                  child: const Text("Lost")),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, "stolen"),
                  child: const Text("Stolen")),
            ],
          ),
        );
        if (lostOrStolen != null) {
          await _login(replace: true, replacementReason: lostOrStolen);
        }
      } else if (choice == "current_installation") {
        await _login(recoverInstallation: true);
      } else if (choice == "replaced") {
        await _login(replace: true, replacementReason: "replaced");
      }
    } else if (res["error"] == "DEVICE_REVOKED") {
      await DeviceSecurityService.disableCurrentDevice(
        reason: res["reason"]?.toString(),
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
          context, '/device_disabled', (_) => false);
    } else if (res["error"] == "TRANSFER_REQUIRED") {
      setState(() {
        _errorMessage =
            "Create a transfer code on the old device before replacing it.";
      });
    } else {
      final store = SecureStore();

      if (auto) {
        await store.remove("savedUserPassword");
        await store.setBool("rememberMeUser", false);
      }

      String msg = "Login failed";

      if (res["status"] == 401) {
        msg = "Incorrect password";
      } else if (res["status"] == 404) {
        msg = "Account not found";
      } else if (res["error"] != null) {
        msg = res["error"];
      }

      setState(() {
        _errorMessage = msg;
      });
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _goToReset() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(
          emailOrPhone: _emailCtrl.text.trim(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
                onChanged: (_) => _clearError(),
                decoration: const InputDecoration(labelText: "Email"),
                validator: (v) => v == null || v.isEmpty ? "Enter email" : null,
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
                      _showPassword ? Icons.visibility_off : Icons.visibility,
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
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _goToReset,
                  child: const Text("Forgot Password?"),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                title: const Text("Remember me"),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _login(),
                child: const Text("Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
