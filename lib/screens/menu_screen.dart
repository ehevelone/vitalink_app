// lib/screens/menu_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../models.dart';
import '../services/data_repository.dart';
import '../services/device_security_service.dart';
import '../widgets/safe_bottom_button.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with WidgetsBindingObserver {
  late final DataRepository _repo;
  final SecureStore _store = SecureStore();

  Profile? _p;
  bool _loading = true;
  String _displayName = "User";
  bool _notificationPermissionDialogShown = false;

  bool _syncRan = false;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    debugPrint("MENU INIT HIT");

    _repo = DataRepository(_store);

    _loadProfile();
    _refreshSharedAccess();
    _setupFCM();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_syncRan) return;
    _syncRan = true;

    debugPrint("SYNC STARTING");

    ApiService.syncProfilesToServer()
        .then((_) => debugPrint("SYNC COMPLETE"))
        .catchError((e) => debugPrint("SYNC ERROR: $e"));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfile();
      _registerToken();
      _checkDeviceAndSharedAccess();

      // 🔥 ADDED — refresh QR on resume
      _refreshQr();
    }
  }

  Future<void> _checkDeviceAndSharedAccess() async {
    final active = await DeviceSecurityService.checkCurrentDevice();
    if (!mounted) return;
    if (!active) {
      Navigator.pushNamedAndRemoveUntil(
          context, '/device_disabled', (_) => false);
      return;
    }
    await _refreshSharedAccess();
  }

  Future<void> _refreshSharedAccess() async {
    final userId = await _store.getString('userId');
    if (userId == null) return;
    final result = await ApiService.getSharedProfileStatuses(userId: userId);
    final relationships = result['relationships'] is List
        ? (result['relationships'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    if (result['success'] == true) {
      await _repo.applySharedAccessStatuses(relationships);
      final profiles = await _repo.loadAllProfiles();
      final activeIndex = await _repo.getActiveProfileIndex();
      if (profiles.isNotEmpty &&
          activeIndex >= 0 &&
          activeIndex < profiles.length &&
          profiles[activeIndex].sharedAccessStatus == 'revoked') {
        final availableIndex = profiles.indexWhere(
          (profile) => profile.sharedAccessStatus != 'revoked',
        );
        if (availableIndex >= 0) {
          await _repo.setActiveProfileIndex(availableIndex);
        }
      }
      await _loadProfile();
    }
  }

  // 🔥 ADDED — QR REFRESH FUNCTION
  Future<void> _refreshQr() async {
    try {
      if (_p == null || _p!.id.isEmpty) return;

      final res = await ApiService.getProfiles(_p!.id);

      if (res["success"] != true) return;

      final profiles = res["profiles"] as List;

      Map<String, dynamic>? match;
      for (final x in profiles) {
        if (x["id"].toString() == _p!.id.toString()) {
          match = x;
          break;
        }
      }

      match ??= profiles.isNotEmpty ? profiles.first : null;

      final qrToken = match?["qr_token"]?.toString();

      if (qrToken == null || qrToken.isEmpty) return;

      final qrUrl = "https://myvitalink.app/emergency.html?token=$qrToken";

      await _store.setString("qr_url", qrUrl);

      debugPrint("QR UPDATED");
    } catch (e) {
      debugPrint("QR REFRESH FAILED: $e");
    }
  }

  Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token != null && token.isNotEmpty) {
        final userId = await _store.getString("userId");

        if (userId == null) return;

        await ApiService.registerDeviceToken(
          userId: userId,
          fcmToken: token,
        );

        debugPrint("FCM TOKEN REGISTERED");
      }
    } catch (e) {
      debugPrint("Token registration error: $e");
    }
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _repo.loadProfile();
      final storedName = await _store.getString("userName");

      String name = "";

      if (p.fullName.trim().isNotEmpty) {
        name = p.fullName.trim();
        await _store.setString("userName", name);
      } else if (storedName != null && storedName.trim().isNotEmpty) {
        name = storedName.trim();
      } else {
        name = "User";
      }

      if (!mounted) return;

      setState(() {
        _p = p;
        _displayName = name;
        _loading = false;
      });

      // 🔥 ADDED — refresh QR AFTER profile loads
      await _refreshQr();
    } catch (e) {
      debugPrint("Profile load error: $e");

      if (!mounted) return;

      setState(() {
        _displayName = "User";
        _loading = false;
      });
    }
  }

  Future<void> _setupFCM() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        _showNotificationPermissionDialog();
        return;
      }

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (Platform.isIOS) {
        for (int i = 0; i < 10; i++) {
          final apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      await _registerToken();

      await _tokenSub?.cancel();
      _tokenSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final userId = await _store.getString("userId");

        if (userId == null) return;

        await ApiService.registerDeviceToken(
          userId: userId,
          fcmToken: newToken,
        );

        debugPrint("FCM TOKEN REFRESHED");
      });

      await _messageSub?.cancel();
      _messageSub = FirebaseMessaging.onMessage.listen((message) {
        debugPrint("FOREGROUND NOTIFICATION RECEIVED");

        if (message.data['type'] == 'profile_share_revoked') {
          _refreshSharedAccess();
        }
      });
    } catch (e) {
      debugPrint("FCM error: $e");
    }
  }

  void _showNotificationPermissionDialog() {
    if (!mounted || _notificationPermissionDialogShown) return;
    _notificationPermissionDialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "Allow Notifications",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            "VitaLink needs notifications turned on so you can receive important alerts, profile updates, and messages from your agent.",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              child: const Text("Later"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (Navigator.canPop(context)) Navigator.pop(context);
                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7ED6F8),
                foregroundColor: Colors.black,
              ),
              child: const Text("Open Settings"),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _logout(BuildContext context) async {
    await _store.remove('userLoggedIn');
    await _store.remove('rememberMe');
    await _store.remove('role');
    await _store.remove('authToken');
    await _store.remove('userEmail');

    await AppState.clearAuth();

    if (!context.mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/landing',
      (route) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenSub?.cancel();
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        title: Text(
          "Welcome $_displayName",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset(
              "assets/images/app_icon_big.png",
              height: 32,
              cacheHeight: 96,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Opacity(
                opacity: 0.18,
                child: Image.asset(
                  "assets/images/logo_icon.png",
                  width: MediaQuery.of(context).size.width * 0.9,
                  cacheWidth: 1024,
                ),
              ),
            ),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _item(Icons.person_pin_circle, "My Agent",
                                '/my_agent_user'),
                            _item(Icons.medical_information, "Medications",
                                '/meds'),
                            _item(Icons.people, "Doctors", '/doctors'),
                            _item(Icons.event_available, "Appointments",
                                '/appointments'),
                            _item(Icons.credit_card, "Insurance Cards",
                                '/insurance_cards_menu'),
                            _item(Icons.policy, "Insurance Policies",
                                '/insurance_policies'),
                            _item(
                                Icons.person, "My Profile", '/my_profile_user'),
                            _item(Icons.share, "Profile Sharing",
                                '/profile_sharing'),
                            _item(Icons.sync, "Profile Updates",
                                '/profile_updates'),
                            _item(Icons.settings, "Settings", '/settings'),
                          ],
                        ),
                      ),
                      SafeBottomButton(
                        label: "Add Family Member",
                        icon: Icons.group_add,
                        color: Colors.blue.shade700,
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/new_profile',
                        ).then((_) => _loadProfile()),
                      ),
                      SafeBottomButton(
                        label: "Switch Profile",
                        icon: Icons.swap_horiz,
                        color: Colors.grey.shade900,
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/profile_picker',
                        ).then((_) => _loadProfile()),
                      ),
                      SafeBottomButton(
                        label: "Emergency Info",
                        icon: Icons.warning_amber_rounded,
                        color: Colors.red.shade800,
                        onPressed: () =>
                            Navigator.pushNamed(context, '/emergency'),
                      ),
                      SafeBottomButton(
                        label: "Log Out",
                        icon: Icons.logout,
                        color: Colors.pink.shade100,
                        onPressed: () => _logout(context),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String text, String route) {
    return ListTile(
      tileColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: Colors.black12),
      ),
      leading: Icon(icon, color: Colors.green),
      title: Text(text),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}
