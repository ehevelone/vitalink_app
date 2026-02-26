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
import 'screens/insurance_cards_menu.dart';
import 'screens/insurance_cards_menu_ios.dart';
import 'screens/insurance_card_detail.dart';

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

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint("❌ FlutterError: ${details.exception}");
    debugPrint("${details.stack}");
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: DefaultTextStyle(
              style: const TextStyle(
                  color: Colors.black, fontSize: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "VitaLink crashed while starting",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(details.exceptionAsString()),
                  const SizedBox(height: 12),
                  if (details.stack != null)
                    Text(details.stack.toString()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };

  await runZonedGuarded(() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    try {
      await Firebase.initializeApp();
    } catch (e, st) {
      debugPrint("❌ Firebase.initializeApp failed: $e");
      debugPrint("$st");
    }

    try {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (_) {}

    try {
      await _setupFirebaseTokenListener();
    } catch (_) {}

    runApp(const VitaLinkApp());
  }, (error, stack) {
    debugPrint("❌ Zoned error: $error");
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

  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final email = await store.get('lastEmail');
    final role = await store.get('lastRole');

    if (email != null && role != null) {
      await ApiService.registerDeviceToken(
        email: email,
        fcmToken: newToken,
        role: role,
      );
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _handleNotificationNavigation(message);
  });

  final initialMessage = await fcm.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationNavigation(initialMessage);
  }
}

void _handleNotificationNavigation(RemoteMessage message) {
  final type = message.data['type'];

  if (type == 'hipaa') {
    navigatorKey.currentState
        ?.pushNamed('/authorization_form');
  }

  if (type == 'emergency') {
    navigatorKey.currentState
        ?.pushNamed('/emergency');
  }
}

class VitaLinkApp extends StatelessWidget {
  const VitaLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'VitaLink',
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      routes: {
        '/landing': (context) => const LandingScreen(),
        '/splash': (context) => const SplashScreen(),

        '/my_profile': (context) =>
            const EditProfileScreen(),

        '/terms_user': (context) =>
            const TermsUserScreen(),
        '/registration': (context) =>
            const RegistrationScreen(),
        '/login': (context) => const LoginScreen(),
        '/account_setup': (context) =>
            const AccountSetupScreen(),
        '/welcome': (context) =>
            const WelcomeScreen(),
        '/menu': (context) => MenuScreen(),
        '/my_agent_user': (context) =>
            MyAgentUser(),
        '/my_profile_user': (context) =>
            const ProfileUserScreen(),

        '/profile_picker': (context) =>
            const ProfilePickerScreen(),
        '/new_profile': (context) =>
            const NewProfileScreen(),

        '/terms_agent': (context) =>
            const TermsAgentScreen(),
        '/agent_registration': (context) =>
            const AgentRegistrationScreen(),
        '/agent_login': (context) =>
            const AgentLoginScreen(),
        '/agent_setup': (context) =>
            const AgentSetupScreen(),
        '/agent_menu': (context) =>
            AgentMenuScreen(),
        '/my_agent_agent': (context) =>
            MyAgentAgent(),
        '/my_profile_agent': (context) =>
            const ProfileAgentScreen(),

        '/logo': (context) => const LogoScreen(),
        '/emergency': (context) =>
            EmergencyScreen(),
        '/emergency_view': (context) =>
            EmergencyView(),

        '/meds': (context) => MedsScreen(),
        '/doctors': (context) =>
            DoctorsScreen(),
        '/doctors_view': (context) =>
            DoctorsView(),
        '/insurance_policies': (context) =>
            InsurancePoliciesScreen(),

        // ✅ PLATFORM SPLIT HERE
        '/insurance_cards_menu': (context) =>
            Platform.isIOS
                ? const InsuranceCardsMenuIOS()
                : InsuranceCardsMenuScreen(),

        '/authorization_form': (context) =>
            const HipaaFormScreen(),

        '/scan_card': (context) => ScanCard(),

        '/request_reset': (context) =>
            const RequestResetScreen(),
        '/reset_password': (context) =>
            const ResetPasswordScreen(),

        '/agent_request_reset': (context) =>
            const AgentRequestResetScreen(),
        '/agent_reset_password': (context) =>
            const AgentResetPasswordScreen(),
      },
    );
  }
}