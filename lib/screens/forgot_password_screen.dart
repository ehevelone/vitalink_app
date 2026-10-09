import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _requestReset() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).enterYourEmail)),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await ApiService.requestPasswordReset(
        emailOrPhone: _emailCtrl.text.trim(),
        role: "users",
      );

      if (!mounted) return;

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).resetCodeSentCheck)),
        );
        Navigator.pushReplacementNamed(
          context,
          '/reset_password',
          arguments: _emailCtrl.text.trim(),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(res['error'] ?? AppStrings.of(context).requestFailedX)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).errorMessage('$e'))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).forgotPassword)),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              AppStrings.of(context).forgotPasswordBody,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Column(
              children: [
                TextField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).email,
                    border: InputBorder.none,
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
                    onPressed: _requestReset,
                    icon: const Icon(Icons.send),
                    label: Text(AppStrings.of(context).sendResetCode),
                  ),
          ],
        ),
      ),
    );
  }
}
