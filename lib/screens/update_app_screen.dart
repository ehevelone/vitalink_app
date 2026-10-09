// lib/screens/update_app_screen.dart

import 'dart:io';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateAppScreen extends StatelessWidget {
  const UpdateAppScreen({super.key});

  static const String iosUrl =
      "https://apps.apple.com/us/app/vitalink-by-et-enterprises/id6759175096";

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
        title: Text(AppStrings.of(context).vitalinkUpdate),
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
              Text(
                AppStrings.of(context).newUpdateAvailable,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppStrings.of(context).updateIntro,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                AppStrings.of(context).whatsNew,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              _bullet(AppStrings.of(context).updateNew1),
              _bullet(AppStrings.of(context).updateNew2),
              _bullet(AppStrings.of(context).updateNew3),
              _bullet(AppStrings.of(context).updateNew4),
              const SizedBox(height: 30),
              Text(
                AppStrings.of(context).whyUpdate,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              _bullet(AppStrings.of(context).updateWhy1),
              _bullet(AppStrings.of(context).updateWhy2),
              _bullet(AppStrings.of(context).updateWhy3),
              _bullet(AppStrings.of(context).updateWhy4),
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
                        ? AppStrings.of(context).openAppStore
                        : AppStrings.of(context).openGooglePlay,
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
                  child: Text(
                    AppStrings.of(context).maybeLater,
                    style: const TextStyle(
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
