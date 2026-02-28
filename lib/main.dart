// lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'services/api_service.dart';
import 'services/secure_store.dart';

// Core screens
import 'screens/landing_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/login_screen.dart';
import 'screens/account_setup_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/agent_menu.dart';
import 'screens/agent_registration_screen.dart';
import 'screens/agent_login_screen.dart';
import 'screens/agent_setup_screen.dart';
import 'screens/terms_user_screen.dart';
import 'screens/terms_agent_screen.dart';
import 'screens/logo_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/my_agent_user.dart';
import 'screens/my_agent_agent.dart';
import 'screens/emergency_screen.dart';
import 'screens/emergency_view.dart';

// PROFILE
import 'screens/profile_agent_screen.dart';
import 'screens/profile_user_screen.dart';
import 'screens/edit_profile.dart';
import 'screens/profile_picker.dart';
import 'screens/new_profile_screen.dart';

// Medical / insurance data
import 'screens/meds_screen.dart';
import 'screens/doctors_screen.dart';
import 'screens/doctors_view.dart';
import 'screens/insurance_policies.dart';
import 'screens/insurance_policy_view.dart';
import 'screens/insurance_policy_form.dart';
import 'screens/insurance_cards.dart';
import 'screens/insurance_card_detail.dart';
import 'screens/insurance_cards_menu_ios.dart';

// HIPAA
import 'screens/hipaa_form_screen.dart';

// Utilities
import 'screens/scan_card.dart';

// Password reset
import 'screens/request_reset_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/agent_request_reset_screen.dart';
import 'screens/agent_reset_password_screen.dart';

import 'models.dart';

final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await runZonedGuarded(() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    try {
      await Firebase.initializeApp();
    } catch (_) {}

    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    runApp(const VitaLinkApp());
  }, (error, stack) {
    debugPrint("Zoned error: $error");
    debugPrint("$stack");
  });
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

Future<void> _setupFirebaseTokenListener() async {
  final fcm = FirebaseMessaging.instance;
  final store = SecureStore();

  await fcm.requestPermission();
  final token = await fcm.getToken();

  if (token != null) {
    final email = await store.get('lastEmail');
    final role = await store.get('lastRole');

    if (email != null && role != null) {
      await ApiService.registerDeviceToken(
        email: email,
        fcmToken: token,
        role: role,
      );
    }
  }
}

class VitaLinkApp extends StatefulWidget {
  const VitaLinkApp({super.key});

  @override
  State<VitaLinkApp> createState() => _VitaLinkAppState();
}

class _VitaLinkAppState extends State<VitaLinkApp> {
  @override
  void initState() {
    super.initState();

    // 🔥 FCM disabled for now (was freezing startup)
    // _setupFirebaseTokenListener();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'VitaLink',
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/landing': (context) => const LandingScreen(),
        '/splash': (context) => const SplashScreen(),

        // ✅ RESTORED ROUTES
        '/login': (context) => const LoginScreen(),
        '/agent_login': (context) => const AgentLoginScreen(),
        '/terms_user': (context) => const TermsUserScreen(),
        '/terms_agent': (context) => const TermsAgentScreen(),
        '/registration': (context) => const RegistrationScreen(),
        '/account_setup': (context) => const AccountSetupScreen(),
        '/agent_registration': (context) => const AgentRegistrationScreen(),
        '/agent_setup': (context) => const AgentSetupScreen(),

        '/insurance_cards_menu': (context) => IOSCardScanScreen(),
        '/scan_card': (context) => const ScanCard(),
        '/authorization_form': (context) =>
            const HipaaFormScreen(),
      },
    );
  }
}