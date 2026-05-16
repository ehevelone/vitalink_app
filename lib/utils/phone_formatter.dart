import 'package:flutter/services.dart';

class PhoneNumberFormatter extends TextInputFormatter {
  static String digitsForUsPhone(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 11 && digits.startsWith('1')) {
      digits = digits.substring(1);
    }

    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }

    return digits;
  }

  static String normalizedForApi(String value) {
    final digits = digitsForUsPhone(value);

    return digits.isEmpty ? "" : "+1$digits";
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue) {
    final digits = digitsForUsPhone(newValue.text);

    String formatted = digits;
    if (digits.length >= 1) {
      formatted = "(" + digits.substring(0, digits.length.clamp(0, 3));
    }
    if (digits.length >= 4) {
      formatted = "(" + digits.substring(0, 3) + ") " + digits.substring(3, digits.length.clamp(3, 6));
    }
    if (digits.length >= 7) {
      formatted = "(" +
          digits.substring(0, 3) +
          ") " +
          digits.substring(3, 6) +
          "-" +
          digits.substring(6);
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
