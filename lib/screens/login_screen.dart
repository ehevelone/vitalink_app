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

  void _toast(String msg) {
    // ✅ Never crash if there's no ScaffoldMessenger in the tree yet
    final sm = ScaffoldMessenger.maybeOf(context);
    if (sm == null) {
      debugPrint("⚠️ SnackBar skipped (no ScaffoldMessenger): $msg");
      return;
    }
    sm.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadSavedLogin() async {
    final store = SecureStore();
    final savedEmail = await store.getString('lastEmail');
    final savedPassword = await store.getString('lastPassword');
    final remember = await store.getBool('rememberMe');

    if (!mounted) return;

    if (remember == true && savedEmail != null && savedPassword != null) {
      setState(() {
        _emailCtrl.text = savedEmail;
        _passwordCtrl.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  Future<void> _login() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _loading = true);

    try {
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text.trim();

      // ✅ iOS-only build for now
      final result = await ApiService.loginUser(
        email: email,
        password: password,
        platform: "ios",
      );

      if (!mounted) return;

      if (result['success'] != true) {
        final errorMessage = (result['error']?.toString().trim().isNotEmpty == true)
            ? result['error'].toString()
            : "Login failed";
        _toast(errorMessage);
        setState(() => _loading = false);
        return;
      }

      // ✅ Auth state
      await AppState.setLoggedIn(true);
      await AppState.setEmail(email);
      await AppState.setRole('user');

      // ✅ Remember me
      final store = SecureStore();
      await store.setString('lastEmail', email);

      if (_rememberMe) {
        await store.setBool('rememberMe', true);
        await store.setString('lastPassword', password);
      } else {
        await store.setBool('rememberMe', false);
        await store.remove('lastPassword');
      }

      // ✅ Profile load (never null in your DataRepository)
      final repo = DataRepository();
      await repo.loadProfile();

      if (!mounted) return;

      // ✅ For now just route forward (account setup flow can be reinserted later)
      Navigator.pushReplacementNamed(context, '/logo');
    } catch (e, st) {
      // 🔥 This is what we need to pinpoint the REAL line of the null-bang
      debugPrint("❌ LOGIN EXCEPTION: $e");
      debugPrint("🧱 STACK TRACE:\n$st");

      if (!mounted) return;
      _toast("Login error: $e");
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
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? "Enter your email"
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? "Enter your password"
                    : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (val) => setState(() => _rememberMe = val ?? false),
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
                    MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
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