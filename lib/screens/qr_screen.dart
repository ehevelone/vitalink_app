import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrScreen extends StatelessWidget {
  final String data; // JSON string passed from EmergencyScreen
  final String? title;

  const QrScreen({
    super.key,
    required this.data,
    this.title,
  });

  static const String _baseUrl =
      "https://myvitalink.app/emergency.html";

  @override
  Widget build(BuildContext context) {
    // Encode JSON → base64url
    final encoded =
        base64UrlEncode(utf8.encode(data));

    final qrUrl = "$_baseUrl?data=$encoded";

    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? "Emergency QR"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: QrImageView(
              data: qrUrl,
              size: 280,
              backgroundColor: Colors.white,
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            "Emergency Access",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          const Text(
            "Scan this QR code to view emergency information.\n\n"
            "If the page shows “Session expired”, rescan the QR.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
