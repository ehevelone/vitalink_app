// lib/screens/menu_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../models.dart';
import '../services/data_repository.dart';
import '../widgets/safe_bottom_button.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with WidgetsBindingObserver {
  late final DataRepository _repo;
  final SecureStore _store = SecureStore();

  Profile? _p;
  bool _loading = true;
  String _displayName = "User";

  bool _syncRan = false;
  bool _notificationDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    print("🚀 MENU INIT HIT");

    _repo = DataRepository(_store);

    _loadProfile();
    _setupFCM();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_syncRan) return;
    _syncRan = true;

    print("🔥 SYNC STARTING");

    ApiService.syncProfilesToServer()
        .then((res) => print("✅ SYNC RESULT: $res"))
        .catchError((e) => print("❌ SYNC ERROR: $e"));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfile();
      _registerToken();

      // 🔥 ADDED — refresh QR on resume
      _refreshQr();
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

      final qrUrl =
          "https://myvitalink.app/emergency.html?token=$qrToken";

      await _store.setString("qr_url", qrUrl);

      print("✅ QR UPDATED: $qrUrl");
    } catch (e) {
      print("❌ QR REFRESH FAILED: $e");
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

        print("✅ FCM TOKEN REGISTERED: $token");
      }
    } catch (e) {
      print("Token registration error: $e");
    }
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _repo.loadProfile();
      final storedName = await _store.getString("userName");

      String name = "";

      if (p?.fullName.trim().isNotEmpty == true) {
        name = p!.fullName.trim();
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
      print("Profile load error: $e");

      if (!mounted) return;

      setState(() {
        _displayName = "User";
        _loading = false;
      });
    }
  }

  Future<void> _setupFCM() async {
    try {
      final settings =
          await FirebaseMessaging.instance.requestPermission();

      if (settings.authorizationStatus !=
          AuthorizationStatus.authorized) {
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
          final apns =
              await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      await _registerToken();

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final userId = await _store.getString("userId");

        if (userId == null) return;

        await ApiService.registerDeviceToken(
          userId: userId,
          fcmToken: newToken,
        );

        print("🔁 TOKEN REFRESHED: $newToken");
      });

      FirebaseMessaging.onMessage.listen((message) {
        print("📩 FOREGROUND MESSAGE: ${message.data}");
        print(
          "📩 FOREGROUND NOTIFICATION: "
          "${message.notification?.title} / ${message.notification?.body}",
        );

        _handleNotificationTap(message);

        if (!mounted || _notificationDialogOpen) return;

        final title =
            message.notification?.title ??
            message.data["title"] ??
            "New Notification";

        final body =
            message.notification?.body ??
            message.data["body"] ??
            "You have a new notification";

        _notificationDialogOpen = true;

        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF111111),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              body,
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                  _notificationDialogOpen = false;
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.greenAccent,
                ),
                child: const Text(
                  "OK",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ).then((_) {
          _notificationDialogOpen = false;
        });
      });

      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          _handleNotificationTap(message);
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleNotificationTap(message);
      });

    } catch (e) {
      print("FCM error: $e");
    }
  }

  void _handleNotificationTap(RemoteMessage message) {}

  Future<void> _logout(BuildContext context) async {
    await _store.remove('userLoggedIn');
    await _store.remove('rememberMe');
    await _store.remove('role');
    await _store.remove('authToken');
    await _store.remove('userEmail');

    await AppState.clearAuth();

    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/landing',
      (route) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                            _item(Icons.credit_card, "Insurance Cards",
                                '/insurance_cards_menu'),
                            _item(Icons.policy, "Insurance Policies",
                                '/insurance_policies'),
                            _item(Icons.person, "My Profile",
                                '/my_profile_user'),
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
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Colors.green),
        title: Text(text),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}