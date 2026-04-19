// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';

import 'services/api_service.dart';
import 'services/secure_store.dart';

// SCREENS
import 'screens/landing_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/agent_login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/account_setup_screen.dart';
import 'screens/agent_registration_screen.dart';
import 'screens/agent_setup_screen.dart';
import 'screens/terms_user_screen.dart';
import 'screens/terms_agent_screen.dart';
import 'screens/logo_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/agent_menu.dart';
import 'screens/my_agent_user.dart';
import 'screens/my_agent_agent.dart';
import 'screens/emergency_screen.dart';
import 'screens/emergency_view.dart';
import 'screens/agent_clients_screen.dart';

// PROFILE
import 'screens/profile_user_screen.dart';
import 'screens/profile_agent_screen.dart';
import 'screens/edit_profile.dart';
import 'screens/profile_picker.dart';
import 'screens/new_profile_screen.dart';

// MEDICAL
import 'screens/meds_screen.dart';
import 'screens/doctors_screen.dart';
import 'screens/doctors_view.dart';
import 'screens/insurance_policies.dart';
import 'screens/insurance_cards.dart';
import 'screens/insurance_cards_menu_ios.dart';

// HIPAA
import 'screens/hipaa_form_screen.dart';

// UTIL
import 'screens/scan_card.dart';

// PASSWORD
import 'screens/request_reset_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/agent_request_reset_screen.dart';
import 'screens/agent_reset_password_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🔥 POPUP
void showGlobalNotificationPopup(RemoteMessage message) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;

  final data = message.data;

  showDialog(
    context: ctx,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: Text(data["title"] ?? "New Notification"),
        content: Text(data["body"] ?? "You have a new update."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Dismiss"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("Open"),
          ),
        ],
      );
    },
  );
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// 🔥 REMOVED ORDER APPROVAL NAVIGATION
void _handleNotificationNavigation(RemoteMessage message) {
  debugPrint("📩 TAP DATA: ${message.data}");
}

Future<void> _setupFCMGlobal() async {
  try {
    final messaging = FirebaseMessaging.instance;

    final token = await messaging.getToken();

    final store = SecureStore();

    if (token != null) {
      final userId = await store.getString("userId");

      print("USER ID FOR DEVICE: $userId");

      if (userId != null) {
        await ApiService.registerDeviceToken(
          userId: userId,
          fcmToken: token,
        );
      }
    }

    messaging.onTokenRefresh.listen((newToken) async {
      final userId = await store.getString("userId");

      if (userId != null) {
        await ApiService.registerDeviceToken(
          userId: userId,
          fcmToken: newToken,
        );
      }
    });

  } catch (e) {
    print("❌ FCM ERROR: $e");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await runZonedGuarded(() async {

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    await Firebase.initializeApp();
    await _setupFCMGlobal();

    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    FirebaseMessaging.onMessage.listen((message) {
      showGlobalNotificationPopup(message);
    });

    runApp(const VitaLinkApp());

  }, (error, stack) {
    debugPrint('ZONED ERROR: $error');
  });
}

class VitaLinkApp extends StatefulWidget {
  const VitaLinkApp({super.key});

  @override
  State<VitaLinkApp> createState() => _VitaLinkAppState();
}

class _VitaLinkAppState extends State<VitaLinkApp> {

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'VitaLink',
      debugShowCheckedModeBanner: false,
      home: const LandingScreen(),

      onGenerateRoute: (settings) {
        if (settings.name == '/insurance_cards') {
          int index = 0;
          final args = settings.arguments;

          if (args is int) index = args;
          if (args is Map && args['index'] is int) {
            index = args['index'];
          }

          return MaterialPageRoute(
            builder: (_) => InsuranceCardsScreen(index: index),
          );
        }

        return null;
      },

      routes: {
        '/landing': (context) => const LandingScreen(),
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/agent_login': (context) => const AgentLoginScreen(),
        '/registration': (context) => const RegistrationScreen(),
        '/account_setup': (context) => const AccountSetupScreen(),
        '/agent_registration': (context) => const AgentRegistrationScreen(),
        '/agent_setup': (context) => const AgentSetupScreen(),
        '/terms_user': (context) => const TermsUserScreen(),
        '/terms_agent': (context) => const TermsAgentScreen(),
        '/logo': (context) => const LogoScreen(),
        '/menu': (context) => const MenuScreen(),
        '/agent_menu': (context) => const AgentMenuScreen(),
        '/agent_clients': (context) => const AgentClientsScreen(),
        '/my_agent_user': (context) => const MyAgentUser(),
        '/my_agent_agent': (context) => const MyAgentAgent(),
        '/emergency': (context) => const EmergencyScreen(),
        '/emergency_view': (context) => const EmergencyView(),
        '/my_profile_user': (context) => const ProfileUserScreen(),
        '/my_profile_agent': (context) => const ProfileAgentScreen(),
        '/edit_profile': (context) => const EditProfileScreen(),
        '/profile_picker': (context) => const ProfilePickerScreen(),
        '/new_profile': (context) => const NewProfileScreen(),
        '/meds': (context) => const MedsScreen(),
        '/doctors': (context) => const DoctorsScreen(),
        '/doctors_view': (context) => const DoctorsView(),
        '/insurance_policies': (context) => const InsurancePoliciesScreen(),
        '/insurance_cards_menu': (context) => const IOSCardScanScreen(),
        '/scan_card': (context) => const ScanCard(),
        '/authorization_form': (context) => const HipaaFormScreen(),
        '/request_reset': (context) => const RequestResetScreen(),
        '/reset_password': (context) => const ResetPasswordScreen(),
        '/agent_request_reset': (context) => const AgentRequestResetScreen(),
        '/agent_reset_password': (context) => const AgentResetPasswordScreen(),
      },
    );
  }
}