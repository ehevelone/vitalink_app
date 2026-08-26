// lib/screens/update_app_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateAppScreen extends StatelessWidget {
  const UpdateAppScreen({super.key});

  // 🔥 REPLACE WITH YOUR REAL APPLE APP ID
  static const String iosUrl =
      "https://apps.apple.com/us/app/vitalink/idYOUR_APP_ID";

  static const String androidUrl =
      "https://play.google.com/store/apps/details?id=com.etnaturals.vitalinkapp";

  Future<void> _openStore() async {
    final url = Platform.isIOS ? iosUrl : androidUrl;

    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("VitaLink Update"),
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Center(
                child: Icon(
                  Icons.system_update,
                  size: 90,
                  color: Colors.blue.shade300,
                ),
              ),

              const SizedBox(height: 30),

              const Text(
                "A New VitaLink Update is Available",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                "We’re continually improving VitaLink to make managing and sharing your important information easier and more secure.",
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.white70,
                ),
              ),

              const SizedBox(height: 30),

              const Text(
                "What's New",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 16),

              _bullet("Improved performance and reliability"),
              _bullet("Enhanced notification support"),
              _bullet("Better account and agent linking"),
              _bullet("General bug fixes and stability improvements"),

              const SizedBox(height: 30),

              const Text(
                "Why Update?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 16),

              _bullet("Access the latest VitaLink features"),
              _bullet("Improve app security and protection"),
              _bullet("Ensure better device compatibility"),
              _bullet("Experience faster and more reliable performance"),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openStore,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(
                    Platform.isIOS
                        ? "Open App Store"
                        : "Open Google Play",
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.grey.shade700,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Maybe Later",
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Icon(
            Icons.check_circle,
            color: Colors.blue.shade300,
            size: 22,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.4,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}