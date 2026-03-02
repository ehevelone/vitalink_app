import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/app_state.dart';
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

  bool _loading = false;
  bool _showPassword = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedLogin();
  }

  // 🔥 Always restore email. Restore password only if rememberMe true.
  Future<void> _loadSavedLogin() async {
    final store = SecureStore();

    final savedEmail = await store.getString('lastEmail');
    final savedPassword = await store.getString('lastPassword');
    final remember = await store.getBool('rememberMe');

    if (!mounted) return;

    setState(() {
      if (savedEmail != null && savedEmail.isNotEmpty) {
        _emailCtrl.text = savedEmail;
      }

      if (remember == true && savedPassword != null) {
        _passwordCtrl.text = savedPassword;
        _rememberMe = true;
      } else {
        _rememberMe = false;
      }
    });
  }

  void _toast(String msg) {
    final sm = ScaffoldMessenger.maybeOf(context);
    if (sm != null) {
      sm.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text.trim();

      final result = await ApiService.loginUser(
        email: email,
        password: password,
        platform: "ios",
      );

      if (!mounted) return;

      if (result['success'] != true) {
        _toast(result['error'] ?? "Login failed");
        setState(() => _loading = false);
        return;
      }

      // ✅ AppState
      await AppState.setLoggedIn(true);
      await AppState.setEmail(email);
      await AppState.setRole('user');

      // ✅ SecureStore (used by logo + device reg)
      final store = SecureStore();
      await store.setString('userEmail', email);
      await store.setString('role', 'user');
      await store.setBool('userLoggedIn', true);

      // 🔥 Always store last email
      await store.setString('lastEmail', email);

      // 🔥 Proper remember logic
      await store.setBool('rememberMe', _rememberMe);

      if (_rememberMe) {
        await store.setString('lastPassword', password);
      } else {
        await store.remove('lastPassword');
      }

      await DataRepository().loadProfile();

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/logo');
    } catch (_) {
      if (!mounted) return;
      _toast("Login error");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      appBar: AppBar(title: const Text("User Login")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: "Email"),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "Enter your email" : null,
              ),
              const SizedBox(height: 16),
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
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty
                        ? "Enter your password"
                        : null,
              ),
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (val) =>
                        setState(() => _rememberMe = val ?? false),
                  ),
                  const Text("Remember Me"),
                ],
              ),
              const SizedBox(height: 24),
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text("Login"),
                    ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ResetPasswordScreen(),
                    ),
                  );
                },
                child: const Text("Forgot Password?"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}