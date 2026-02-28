import 'dart:io';
import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
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
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _loadSavedLogin();
  }

  Future<void> _loadSavedLogin() async {
    final store = SecureStore();
    final savedEmail = await store.getString('lastEmail');
    final loggedIn = await store.getBool('userLoggedIn');

    if (savedEmail != null && loggedIn == true) {
      _emailCtrl.text = savedEmail;
      setState(() {
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

      final result = await ApiService.loginUser(
        email: email,
        password: password,
        platform: Platform.isIOS ? "ios" : "android",
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final store = SecureStore();
        final repo = DataRepository();

        if (_rememberMe) {
          await store.setBool('userLoggedIn', true);
          await store.setString('lastEmail', email);
          await store.setString('lastRole', 'user');
        } else {
          await store.setBool('userLoggedIn', false);
          await store.delete('lastEmail');
        }

        final profile = await repo.loadProfile();

        if (!mounted) return;

        if (profile == null) {
          Navigator.pushReplacementNamed(context, '/account_setup');
        } else {
          Navigator.pushReplacementNamed(context, '/menu');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? "Login failed"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
                    v == null || v.isEmpty ? "Enter your email" : null,
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
                    v == null || v.isEmpty ? "Enter your password" : null,
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (v) {
                      setState(() => _rememberMe = v ?? false);
                    },
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
                      builder: (_) =>
                          const ResetPasswordScreen(),
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