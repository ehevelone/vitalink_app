import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_strings.dart';

class QrScreen extends StatelessWidget {
  final String qrToken;
  final String? title;

  const QrScreen({
    super.key,
    required this.qrToken,
    this.title,
  });

  static const String _baseUrl = "https://myvitalink.app/emergency.html";

  @override
  Widget build(BuildContext context) {
    final qrUrl = "$_baseUrl?token=$qrToken";
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? strings.emergencyQr),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final qrSize = math
              .max(
                180.0,
                math.min(
                  constraints.maxWidth - 40,
                  math.min(constraints.maxHeight * 0.55, 340),
                ),
              )
              .toDouble();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: SizedBox.square(
                  dimension: qrSize,
                  child: QrImageView(
                    data: qrUrl,
                    size: qrSize,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                strings.emergencyAccess,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                strings.emergencyQrInstructions,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
