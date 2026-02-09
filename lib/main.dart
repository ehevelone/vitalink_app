// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Firebase core only (NO messaging init yet)
import 'package:firebase_core/firebase_core.dart';

// ✅ ADD: FCM + local notifications (for foreground display)
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Local services
import 'services/api_service.dart';
import 'services/secure_store.dart';

// Core screens
import 'screens/landing_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/login_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/agent_menu.dart';
import 'screens/agent_registration_screen.dart';
import 'screens/agent_login_screen.dart';
import 'screens/terms_user_screen.dart';
import 'screens/terms_agent_screen.dart';
import 'screens/logo_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/my_agent_user.dart';
import 'screens/my_agent_agent.dart';
import 'screens/emergency_screen.dart';
import 'screens/emergency_view.dart';
import 'screens/my_profile_screen.dart';

// Medical / Insurance
import 'screens/meds_screen.dart';
import 'screens/doctors_screen.dart';
import 'screens/doctors_view.dart';
import 'screens/insurance_policies.dart';
import 'screens/insurance_policy_view.dart';
import 'screens/insurance_policy_form.dart';
import 'screens/insurance_cards.dart';
import 'screens/insurance_cards_menu.dart';
import 'screens/insurance_card_detail.dart';

// HIPAA + SOA
import 'screens/hipaa_form_screen.dart';

// Utilities
import 'screens/scan_card.dart';

// Password reset
import 'screens/request_reset_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/agent_request_reset_screen.dart';
import 'screens/agent_reset_password_screen.dart';

// Household / Family profiles
import 'screens/new_profile_screen.dart';
import 'screens/profile_picker.dart';
import 'screens/profile_manager.dart';

import 'models.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const MethodChannel _navChannel = MethodChannel("vitalink/navigation");

// ✅ ADD: local notifications plugin (foreground notification display)
final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await localNotifications.initialize(initSettings);
}

// ✅ ADD: show notifications while app is OPEN (foreground)
void _setupForegroundNotifications() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'vitalink_alerts',
      'VitaLink Alerts',
      channelDescription: 'Important VitaLink notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const platformDetails = NotificationDetails(android: androidDetails);

    await localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformDetails,
    );
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // ✅ Local notifications init is safe even if Firebase fails
  try {
    await _initLocalNotifications();
  } catch (e, st) {
    debugPrint('🔥 Local notifications init failed: $e');
    debugPrint('$st');
  }

  // Firebase init wrapped so it can't crash startup
  try {
    await Firebase.initializeApp();

    // ✅ Wire foreground notifications ONLY after Firebase is ready
    _setupForegroundNotifications();
  } catch (e, st) {
    debugPrint('🔥 Firebase initialization failed: $e');
    debugPrint('$st');
  }

  runApp(const VitaLinkApp());

  // Lock screen shortcut only (safe)
  _navChannel.setMethodCallHandler((call) async {
    if (call.method == "openEmergency") {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/emergency',
        (route) => false,
      );
    }
    return null;
  });

  // IMPORTANT:
  // Messaging, token refresh, background handlers are DISABLED until app boots.
}

class VitaLinkApp extends StatelessWidget {
  const VitaLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VitaLink',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
      initialRoute: '/splash',
      routes: {
        '/landing': (_) => const LandingScreen(),
        '/splash': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/agent_login': (_) => const AgentLoginScreen(),
        '/menu': (_) => const MenuScreen(),
        '/agent_menu': (_) => AgentMenuScreen(),
        '/terms_user': (_) => const TermsUserScreen(),
        '/terms_agent': (_) => const TermsAgentScreen(),
        '/registration': (_) => const RegistrationScreen(),
        '/agent_registration': (_) => const AgentRegistrationScreen(),
        '/welcome': (_) => const WelcomeScreen(),
        '/my_profile': (_) => const MyProfileScreen(),
        '/logo': (_) => const LogoScreen(),
        '/my_agent_user': (_) => MyAgentUser(),
        '/my_agent_agent': (_) => MyAgentAgent(),
        '/emergency': (_) => EmergencyScreen(),
        '/emergency_view': (_) => EmergencyView(),
        '/meds': (_) => MedsScreen(),
        '/doctors': (_) => DoctorsScreen(),
        '/doctors_view': (_) => DoctorsView(),
        '/insurance_policies': (_) => InsurancePoliciesScreen(),
        '/insurance_cards_menu': (_) => InsuranceCardsMenuScreen(),
        '/authorization_form': (_) => const HipaaFormScreen(),
        '/new_profile': (_) => const NewProfileScreen(),
        '/profile_picker': (_) => const ProfilePickerScreen(),
        '/profile_manager': (_) => const ProfileManagerScreen(),
        '/scan_card': (_) => ScanCard(),
        '/request_reset': (_) => const RequestResetScreen(),
        '/reset_password': (_) => const ResetPasswordScreen(),
        '/agent_request_reset': (_) => const AgentRequestResetScreen(),
        '/agent_reset_password': (_) => const AgentResetPasswordScreen(),
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/insurance_policy_view':
            return MaterialPageRoute(
              builder: (_) =>
                  InsurancePolicyView(index: settings.arguments as int),
            );

          case '/insurance_policy_form':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (_) => InsurancePolicyForm(
                policy: args['policy'] as Insurance,
                allPolicies: args['allPolicies'] as List<Insurance>,
              ),
            );

          case '/insurance_cards':
            return MaterialPageRoute(
              builder: (_) =>
                  InsuranceCardsScreen(index: settings.arguments as int),
            );

          case '/insurance_card_detail':
            return MaterialPageRoute(
              builder: (_) => InsuranceCardDetail(
                card: settings.arguments as InsuranceCard,
              ),
            );

          case '/reset_password':
            final emailOrPhone = settings.arguments as String?;
            return MaterialPageRoute(
              builder: (_) => ResetPasswordScreen(
                emailOrPhone: emailOrPhone,
              ),
            );

          case '/agent_reset_password':
            final emailOrPhone = settings.arguments as String?;
            return MaterialPageRoute(
              builder: (_) => AgentResetPasswordScreen(
                emailOrPhone: emailOrPhone,
              ),
            );
        }
        return null;
      },
    );
  }
}
