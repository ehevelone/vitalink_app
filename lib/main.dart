// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

    runApp(const VitaLinkApp());
  }, (error, stack) {
    debugPrint("ZONED ERROR: $error");
    debugPrint(stack.toString());
  });
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

        '/my_agent_user': (context) => const MyAgentUser(),
        '/my_agent_agent': (context) => const MyAgentAgent(),

        '/emergency': (context) => const EmergencyScreen(),
        '/emergency_view': (context) => const EmergencyView(),

        '/my_profile_user': (context) => const ProfileUserScreen(),
        '/my_profile_agent': (context) => const ProfileAgentScreen(),
        '/edit_profile': (context) => EditProfile(),
        '/profile_picker': (context) => ProfilePicker(),
        '/new_profile': (context) => const NewProfileScreen(),

        '/meds': (context) => const MedsScreen(),
        '/doctors': (context) => const DoctorsScreen(),
        '/doctors_view': (context) => const DoctorsView(),

        '/insurance_policies': (context) => InsurancePolicies(),
        '/insurance_cards': (context) => InsuranceCards(),
        '/insurance_cards_menu': (context) =>
            const IOSCardScanScreen(),

        '/scan_card': (context) => const ScanCard(),
        '/authorization_form': (context) =>
            const HipaaFormScreen(),

        '/request_reset': (context) => const RequestResetScreen(),
        '/reset_password': (context) => const ResetPasswordScreen(),
        '/agent_request_reset': (context) =>
            const AgentRequestResetScreen(),
        '/agent_reset_password': (context) =>
            const AgentResetPasswordScreen(),
      },
    );
  }
}