import 'dart:async';
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

class _MenuScreenState extends State<MenuScreen> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;
  StreamSubscription<String>? _tokenSub;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _loadProfile();
    _setupFCM();
  }

  Future<void> _setupFCM() async {
    final store = SecureStore();

    try {
      // 1️⃣ Request permission
      final settings =
          await FirebaseMessaging.instance.requestPermission();

      if (settings.authorizationStatus !=
          AuthorizationStatus.authorized) {
        print("Notifications not authorized");
        return;
      }

      // 2️⃣ Wait for APNs token (iOS only requirement)
      String? apnsToken;
      for (int i = 0; i < 10; i++) {
        apnsToken =
            await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (apnsToken == null) {
        print("APNS token never arrived");
        return;
      }

      print("APNS TOKEN: $apnsToken");

      // 3️⃣ Now get FCM token
      final fcmToken =
          await FirebaseMessaging.instance.getToken();

      if (fcmToken == null) {
        print("FCM token null");
        return;
      }

      print("FCM TOKEN: $fcmToken");

      final email = await store.getString('userEmail');
      final role = await store.getString('role');

      if (email == null || role == null) return;

      await ApiService.registerDeviceToken(
        email: email,
        fcmToken: fcmToken,
        role: role,
      );

      // 4️⃣ Listen for refresh
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh
          .listen((newToken) async {
        await ApiService.registerDeviceToken(
          email: email,
          fcmToken: newToken,
          role: role,
        );
      });
    } catch (e) {
      print("FCM setup error: $e");
    }
  }

  Future<void> _loadProfile() async {
    final p = await _repo.loadProfile();
    if (!mounted) return;
    setState(() {
      _p = p;
      _loading = false;
    });
  }

  Future<void> _logout(BuildContext context) async {
    final store = SecureStore();

    await store.remove('userLoggedIn');
    await store.remove('rememberMe');
    await store.remove('role');
    await store.remove('authToken');
    await store.remove('userEmail');

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
    _tokenSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        (_p?.fullName.isNotEmpty == true) ? _p!.fullName : "User";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        title: Text(
          "Welcome $displayName",
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