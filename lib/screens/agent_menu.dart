import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/secure_store.dart';
import '../services/app_state.dart';
import '../services/api_service.dart';

class AgentMenuScreen extends StatefulWidget {
  const AgentMenuScreen({super.key});

  @override
  State<AgentMenuScreen> createState() => _AgentMenuScreenState();
}

class _AgentMenuScreenState extends State<AgentMenuScreen> {
  bool _loading = true;
  String agentName = "Agent";
  bool _notificationDialogOpen = false;
  bool _notificationPermissionDialogShown = false;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupAgentNotifications();
  }

  Future<void> _registerAgentToken() async {
    try {
      final store = SecureStore();
      final agentIdText = await store.getString("agentId");
      final agentId = int.tryParse(agentIdText ?? "");
      if (agentId == null || agentId <= 0) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await ApiService.registerAgentDeviceToken(
        agentId: agentId,
        fcmToken: token,
      );
    } catch (e) {
      debugPrint("Agent FCM token registration error: $e");
    }
  }

  Future<void> _setupAgentNotifications() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

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

      await _registerAgentToken();

      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        _registerAgentToken();
      });

      _messageSub = FirebaseMessaging.onMessage.listen((message) {
        _showForegroundNotification(message);
      });

      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleAgentNotification(message);
      });

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _handleAgentNotification(initial);
      }
    } catch (e) {
      debugPrint("Agent FCM setup error: $e");
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
            "VitaLink needs notifications turned on so you can receive referral alerts, profile updates, and client messages.",
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

  void _handleAgentNotification(RemoteMessage message) {
    final route = message.data["route"]?.toString();
    if (!mounted || route == null || route.isEmpty) return;

    Navigator.pushNamed(context, route);
  }

  void _showForegroundNotification(RemoteMessage message) {
    if (!mounted || _notificationDialogOpen) return;

    final title = message.notification?.title ??
        message.data["title"] ??
        "New Notification";
    final body = message.notification?.body ??
        message.data["body"] ??
        "You have a new notification";
    final route = message.data["route"]?.toString();

    _notificationDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              if (Navigator.canPop(context)) Navigator.pop(context);
              _notificationDialogOpen = false;
            },
            child: const Text(
              "Dismiss",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
              _notificationDialogOpen = false;
              if (route != null && route.isNotEmpty && mounted) {
                Navigator.pushNamed(context, route);
              }
            },
            child: const Text(
              "Open",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ).then((_) {
      _notificationDialogOpen = false;
    });
  }

  Future<void> _loadData() async {
    final store = SecureStore();
    final storedName = await store.getString("agentName");

    if (!mounted) return;

    setState(() {
      if (storedName != null && storedName.isNotEmpty) {
        agentName = storedName;
      } else {
        agentName = "Agent";
      }

      _loading = false;
    });
  }

  Future<void> _logout(BuildContext context) async {
    await AppState.setLoggedIn(false);
    await AppState.clearAuth();

    final store = SecureStore();
    await store.remove('loggedIn');
    await store.remove('userLoggedIn');
    await store.remove('agentLoggedIn');
    await store.remove('role');
    await store.remove('authToken');
    await store.remove('device_token');
    await store.remove('agentName');
    await store.remove('lastEmail');
    await store.remove('lastRole');

    if (!context.mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/landing',
      (route) => false,
    );
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _openedSub?.cancel();
    _tokenSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: Text(
          "Welcome $agentName",
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
                opacity: 0.06,
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          children: [
                            _item(Icons.badge, "My Agent", '/my_agent_agent'),
                            _item(Icons.person, "My Profile",
                                '/my_profile_agent'),
                            _item(
                              Icons.document_scanner,
                              "Business Card Scanner",
                              '/my_profile_agent',
                              arguments: {'autoScan': true},
                            ),

                            // NEW BUTTON
                            _item(Icons.groups, "My Clients", '/agent_clients'),
                            _item(Icons.favorite, "Referral Center",
                                '/agent_referrals'),
                            _item(Icons.task_alt, "Notes / Tasks", '/agent_notes'),
                            _item(Icons.medical_information, "Medications",
                                '/meds'),
                            _item(Icons.people, "Doctors", '/doctors'),
                            _item(Icons.credit_card, "Insurance Cards",
                                '/insurance_cards_menu'),
                            _item(Icons.policy, "Insurance Policies",
                                '/insurance_policies'),
                          ],
                        ),
                      ),
                      SafeArea(
                        top: false,
                        minimum: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade900,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  icon: const Icon(Icons.warning_amber_rounded),
                                  label: const Text(
                                    "Emergency Info",
                                    style: TextStyle(fontSize: 17),
                                  ),
                                  onPressed: () => Navigator.pushNamed(
                                      context, '/emergency'),
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade100,
                                    foregroundColor: Colors.red.shade700,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  icon: const Icon(Icons.logout),
                                  label: const Text(
                                    "Log Out",
                                    style: TextStyle(fontSize: 17),
                                  ),
                                  onPressed: () => _logout(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    IconData icon,
    String text,
    String route, {
    Object? arguments,
  }) {
    return ListTile(
      tileColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: Colors.black12),
      ),
      leading: Icon(icon, color: Colors.blue),
      title: Text(text, style: const TextStyle(fontSize: 18)),
      onTap: () => Navigator.pushNamed(context, route, arguments: arguments),
    );
  }
}
