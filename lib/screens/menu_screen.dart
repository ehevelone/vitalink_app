// lib/main.dart
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

// ✅ ADD THIS IMPORT
import 'screens/my_profile_screen.dart';

// Medical / insurance data
import 'screens/meds_screen.dart';
import 'screens/doctors_screen.dart';
import 'screens/doctors_view.dart';
import 'screens/insurance_policies.dart';
import 'screens/insurance_policy_view.dart';
import 'screens/insurance_policy_form.dart';
import 'screens/insurance_cards.dart';
import 'screens/insurance_cards_menu.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(
    _firebaseMessagingBackgroundHandler,
  );

  await _setupFirebaseTokenListener();

  runApp(const VitaLinkApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  await Firebase.initializeApp();
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
}

class VitaLinkApp extends StatelessWidget {
  const VitaLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

        // User
        '/terms_user': (context) => const TermsUserScreen(),
        '/registration': (context) => const RegistrationScreen(),
        '/login': (context) => const LoginScreen(),
        '/account_setup': (context) => const AccountSetupScreen(),
        '/welcome': (context) => const WelcomeScreen(),
        '/menu': (context) => const MenuScreen(),
        '/my_agent_user': (context) => const MyAgentUser(),

        // ✅ ADDED ROUTE FIX
        '/my_profile': (context) => const MyProfileScreen(),

        // Agent
        '/terms_agent': (context) => const TermsAgentScreen(),
        '/agent_registration': (context) =>
            const AgentRegistrationScreen(),
        '/agent_login': (context) => const AgentLoginScreen(),
        '/agent_setup': (context) => const AgentSetupScreen(),
        '/agent_menu': (context) => const AgentMenuScreen(),
        '/my_agent_agent': (context) => const MyAgentAgent(),

        // Shared
        '/logo': (context) => const LogoScreen(),
        '/emergency': (context) => const EmergencyScreen(),
        '/emergency_view': (context) => const EmergencyView(),

        // Medical
        '/meds': (context) => const MedsScreen(),
        '/doctors': (context) => const DoctorsScreen(),
        '/doctors_view': (context) => const DoctorsView(),
        '/insurance_policies': (context) =>
            const InsurancePoliciesScreen(),
        '/insurance_cards_menu': (context) =>
            const InsuranceCardsMenuScreen(),

        '/authorization_form': (context) =>
            const HipaaFormScreen(),

        '/scan_card': (context) => const ScanCard(),

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
