import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/device_id.dart';
import '../l10n/app_strings.dart';
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

  Future<bool> _showReplacePopup() async {
    final strings = AppStrings.of(context);

    return await showDialog<bool>(
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
                  Text(
                    strings.newDeviceDetected,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    strings.deviceAlreadyActive,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(strings.yes,
                        style: const TextStyle(color: Colors.black)),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(strings.no,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<void> _login({bool replace = false, bool auto = false}) async {
    if (!auto && !_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();
    final platform =
        Theme.of(context).platform == TargetPlatform.iOS ? "ios" : "android";
    final strings = AppStrings.of(context);
    final deviceId = await DeviceId.getOrCreate();

    final res = await ApiService.loginUser(
      email: email,
      password: password,
      platform: platform,
      deviceId: deviceId,
      replace: replace,
    );

    if (!mounted) return;

    if (res["success"] == true) {
      final user = res["user"];
      final store = SecureStore();

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
      Navigator.pushReplacementNamed(context, "/logo");
    } else if (res["error"] == "DEVICE_ACTIVE" && replace == false) {
      final confirmed = await _showReplacePopup();
      if (confirmed) {
        await _login(replace: true);
      }
    } else {
      final store = SecureStore();

      if (auto) {
        await store.remove("savedUserPassword");
        await store.setBool("rememberMeUser", false);
      }

      String msg = strings.loginFailed;

      if (res["status"] == 401) {
        msg = strings.incorrectPassword;
      } else if (res["status"] == 404) {
        msg = strings.accountNotFound;
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
    final strings = AppStrings.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.userLogin)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _emailCtrl,
                onChanged: (_) => _clearError(),
                decoration: InputDecoration(labelText: strings.email),
                validator: (v) =>
                    v == null || v.isEmpty ? strings.enterEmail : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                onChanged: (_) => _clearError(),
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: strings.password,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? strings.enterPassword : null,
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
                  child: Text(strings.forgotPassword),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                title: Text(strings.rememberMe),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _login(),
                child: Text(strings.login),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
