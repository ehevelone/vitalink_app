import 'package:flutter/material.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/device_id.dart';
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
    try {
      final store = SecureStore();
      final remember = await store
          .getBool("rememberMeUser")
          .timeout(const Duration(seconds: 6));

      if (remember == true) {
        final email = await store
            .getString("savedUserEmail")
            .timeout(const Duration(seconds: 6));
        final pass = await store
            .getString("savedUserPassword")
            .timeout(const Duration(seconds: 6));
        if (!mounted) return;
        _emailCtrl.text = email ?? "";
        _passwordCtrl.text = pass ?? "";
        _rememberMe = true;
      }
    } catch (error) {
      debugPrint('Unable to load saved user login: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _showReplacePopup() async {
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
                  const Text(
                    "New Device Detected",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "This account is already active on another device.\n\nDo you want to switch to this device?",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("YES",
                        style: TextStyle(color: Colors.black)),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child:
                        const Text("NO", style: TextStyle(color: Colors.white)),
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

    var loginStage = 'device storage';
    var sessionWriteStarted = false;
    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      final password = _passwordCtrl.text.trim();
      final deviceId =
          await DeviceId.getOrCreate().timeout(const Duration(seconds: 8));

      final platform =
          !mounted || Theme.of(context).platform == TargetPlatform.iOS
              ? "ios"
              : "android";

      loginStage = 'server';
      final res = await ApiService.loginUser(
        email: email,
        password: password,
        platform: platform,
        deviceId: deviceId,
        replace: replace,
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (res["success"] == true) {
        final user = res["user"];
        final store = SecureStore();

        loginStage = 'session storage';
        sessionWriteStarted = true;
        await store
            .setString("userId", user["id"].toString())
            .timeout(const Duration(seconds: 6));
        await store
            .setString("userEmail", user["email"])
            .timeout(const Duration(seconds: 6));

        final sessionToken = user["session_token"]?.toString() ?? "";
        if (sessionToken.isEmpty) {
          throw StateError('User session token missing');
        }
        await store
            .setString("userSessionToken", sessionToken)
            .timeout(const Duration(seconds: 6));
        await AppState.setRole("user").timeout(const Duration(seconds: 6));
        await AppState.setEmail(user["email"])
            .timeout(const Duration(seconds: 6));
        await AppState.setLoggedIn(true).timeout(const Duration(seconds: 6));

        try {
          if (_rememberMe) {
            await store
                .setBool("rememberMeUser", true)
                .timeout(const Duration(seconds: 6));
            await store
                .setString("savedUserEmail", email)
                .timeout(const Duration(seconds: 6));
            await store
                .setString("savedUserPassword", password)
                .timeout(const Duration(seconds: 6));
          } else {
            await store
                .setBool("rememberMeUser", false)
                .timeout(const Duration(seconds: 6));
            await store
                .remove("savedUserEmail")
                .timeout(const Duration(seconds: 6));
            await store
                .remove("savedUserPassword")
                .timeout(const Duration(seconds: 6));
          }
        } catch (error) {
          debugPrint('Unable to save optional user login details: $error');
        }

        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          "/logo",
          arguments: {
            "justLoggedIn": true,
            "role": "user",
            "userSessionToken": sessionToken,
          },
        );
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
    } catch (error) {
      debugPrint('User login failed at $loginStage: $error');
      if (sessionWriteStarted) {
        try {
          await AppState.clearAuth().timeout(const Duration(seconds: 6));
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _errorMessage = loginStage == 'server'
            ? 'The login connection did not finish. Check your connection and try again.'
            : 'This phone could not finish $loginStage. Your account is unchanged. Please restart VitaLink and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
