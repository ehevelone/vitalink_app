import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_links/app_links.dart';

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

// NEW SCREEN
import 'screens/agent_clients_screen.dart';
import 'screens/order_approval_screen.dart';

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

// 🔥 FIX: GLOBAL NAV QUEUE (THIS WAS MISSING)
String? pendingRoute;
dynamic pendingArgs;

class VitaLinkDeepLink {
  static String? _code;
  static String? _lastRawUri;

  static String? get code => _code;

  static void setCode(String? value, {String? rawUri}) {
    _code = value;
    if (rawUri != null) {
      _lastRawUri = rawUri;
    }
  }

  static bool shouldIgnore(Uri uri) {
    final raw = uri.toString();
    return _lastRawUri == raw;
  }

  static void clear() {
    _code = null;
    _lastRawUri = null;
  }
}

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
    debugPrint('ZONED ERROR: $error');
    debugPrint(stack.toString());
  });
}

class VitaLinkApp extends StatefulWidget {
  const VitaLinkApp({super.key});

  @override
  State<VitaLinkApp> createState() => _VitaLinkAppState();
}

class _VitaLinkAppState extends State<VitaLinkApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;
  bool _linksInitialized = false;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    if (_linksInitialized) return;
    _linksInitialized = true;

    _appLinks = AppLinks();

    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        _storeDeepLink(uri);
      }
    } catch (e) {
      debugPrint('Initial link error: $e');
    }

    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        _storeDeepLink(uri);
      },
      onError: (e) {
        debugPrint('uriLinkStream error: $e');
      },
    );
  }

  void _storeDeepLink(Uri uri) {
    if (VitaLinkDeepLink.shouldIgnore(uri)) return;

    debugPrint('Deep link received: $uri');

    String? code;

    final qpCode = uri.queryParameters['code'];
    if (qpCode != null && qpCode.trim().isNotEmpty) {
      code = qpCode.trim().toUpperCase();
    } else if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) {
        code = last.toUpperCase();
      }
    }

    if (code == null || code.isEmpty) return;

    VitaLinkDeepLink.setCode(code, rawUri: uri.toString());
    debugPrint('Activation code stored: $code');
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

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

          if (args is int) {
            index = args;
          } else if (args is Map) {
            final v = args['index'];
            if (v is int) index = v;
          }

          return MaterialPageRoute(
            settings: settings,
            builder: (_) => InsuranceCardsScreen(index: index),
          );
        }

        if (settings.name == '/orderApproval') {
          int? requestId;
          final args = settings.arguments;

          if (args is int) {
            requestId = args;
          } else if (args is String) {
            requestId = int.tryParse(args);
          } else if (args is Map) {
            final v = args['request_id'] ?? args['requestId'];
            if (v is int) {
              requestId = v;
            } else if (v is String) {
              requestId = int.tryParse(v);
            }
          }

          return MaterialPageRoute(
            settings: settings,
            builder: (_) => OrderApprovalScreen(requestId: requestId),
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