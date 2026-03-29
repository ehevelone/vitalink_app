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

  StreamSubscription<String>? _tokenSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _repo = DataRepository(_store);

    _loadProfile();
    _setupFCM();

    // 🔥 NEW — SILENT PROFILE SYNC (DO NOT AWAIT)
    ApiService.syncProfilesToServer();
  }

  // 🔥 RELOAD WHEN APP COMES BACK (CRITICAL FOR CHEAP DEVICES)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _repo.loadProfile();

      // 🔥 fallback from storage
      final storedName = await _store.getString("userName");

      String name = "";

      if (p?.fullName.trim().isNotEmpty == true) {
        name = p!.fullName.trim();

        // 🔥 keep backup in storage
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

      if (Platform.isIOS) {
        for (int i = 0; i < 10; i++) {
          final apns =
              await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      final token =
          await FirebaseMessaging.instance.getToken();

      if (token == null || token.isEmpty) return;

      final email = await _store.getString('userEmail');
      final role = await _store.getString('role');

      if (email == null || role == null) return;

      await ApiService.registerDeviceToken(
        email: email,
        fcmToken: token,
        role: role,
        platform: Platform.isIOS ? "ios" : "android",
      );

      _tokenSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        final e = await _store.getString('userEmail');
        final r = await _store.getString('role');

        if (e == null || r == null) return;

        await ApiService.registerDeviceToken(
          email: e,
          fcmToken: t,
          role: r,
          platform: Platform.isIOS ? "ios" : "android",
        );
      });
    } catch (e) {
      print("FCM error: $e");
    }
  }

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
    _tokenSub?.cancel();
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