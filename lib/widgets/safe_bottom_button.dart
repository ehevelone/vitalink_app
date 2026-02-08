import 'package:flutter/material.dart';

class SafeBottomButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool loading;
  final Color? color;

  const SafeBottomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.color,
  });

  bool _useDarkText(Color bg) {
    // Simple luminance check for contrast
    return bg.computeLuminance() > 0.6;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? Theme.of(context).primaryColor;
    final useDarkText = _useDarkText(bgColor);
    final fgColor = useDarkText ? Colors.black : Colors.white;

    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: loading ? null : onPressed,
          icon: icon != null
              ? Icon(icon, color: fgColor)
              : Icon(Icons.arrow_forward, color: fgColor),
          label: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(color: fgColor),
                ),
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor,
            foregroundColor: fgColor, // ✅ KEY FIX
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
