import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class PasswordRules extends StatelessWidget {
  final TextEditingController controller;

  const PasswordRules({super.key, required this.controller});

  bool _hasMinLen(String pw) => pw.length >= 10;
  bool _hasUpper(String pw) => RegExp(r'[A-Z]').hasMatch(pw);
  bool _hasSpecial(String pw) => RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(pw);

  @override
  Widget build(BuildContext context) {
    final pw = controller.text;
    final strings = AppStrings.of(context);

    Widget rule(String text, bool ok) {
      return Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              size: 16, color: ok ? Colors.green : Colors.red),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: ok ? Colors.green : Colors.red, fontSize: 13)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        rule(strings.passwordMinLength, _hasMinLen(pw)),
        rule(strings.passwordUppercase, _hasUpper(pw)),
        rule(strings.passwordSpecial, _hasSpecial(pw)),
      ],
    );
  }
}
