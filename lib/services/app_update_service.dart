import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.updateAvailable,
    required this.required,
    required this.currentBuild,
    required this.latestBuild,
    required this.currentVersion,
    required this.latestVersion,
    required this.title,
    required this.message,
    required this.storeUrl,
    required this.releaseNotes,
  });

  final bool updateAvailable;
  final bool required;
  final int currentBuild;
  final int latestBuild;
  final String currentVersion;
  final String latestVersion;
  final String title;
  final String message;
  final String storeUrl;
  final List<String> releaseNotes;
}

class AppUpdateService {
  static const _dismissedBuildKey = 'dismissedUpdateBuild';
  static const _dismissedDateKey = 'dismissedUpdateDate';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    final platform = Platform.isIOS ? 'ios' : 'android';

    final res = await ApiService.checkAppUpdate(
      platform: platform,
      currentBuild: currentBuild,
      currentVersion: packageInfo.version,
    );

    if (res['success'] != true || res['updateAvailable'] != true) {
      return null;
    }

    final latestBuild = _asInt(res['latestBuild']);
    if (latestBuild <= currentBuild) return null;

    final releaseNotes = res['releaseNotes'] is List
        ? (res['releaseNotes'] as List)
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList()
        : <String>[];

    return AppUpdateInfo(
      updateAvailable: true,
      required: res['required'] == true,
      currentBuild: currentBuild,
      latestBuild: latestBuild,
      currentVersion: packageInfo.version,
      latestVersion: (res['latestVersion'] ?? '').toString(),
      title: (res['title'] ?? 'VitaLink Update Available').toString(),
      message: (res['message'] ??
              'A newer version of VitaLink is available. Please update for the latest fixes and improvements.')
          .toString(),
      storeUrl: (res['storeUrl'] ?? '').toString(),
      releaseNotes: releaseNotes,
    );
  }

  static Future<bool> shouldShow(AppUpdateInfo update) async {
    if (update.required) return true;

    final prefs = await SharedPreferences.getInstance();
    final dismissedBuild = prefs.getInt(_dismissedBuildKey);
    final dismissedDate = prefs.getString(_dismissedDateKey);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    return dismissedBuild != update.latestBuild || dismissedDate != today;
  }

  static Future<void> remindLater(AppUpdateInfo update) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    await prefs.setInt(_dismissedBuildKey, update.latestBuild);
    await prefs.setString(_dismissedDateKey, today);
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
