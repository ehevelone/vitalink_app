// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_links/app_links.dart';

import 'services/api_service.dart';
import 'services/secure_store.dart';
import 'services/deep_link_service.dart';
import 'services/language_service.dart';

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
import 'screens/update_app_screen.dart';
import 'screens/agent_notes_screen.dart';
import 'screens/settings_screen.dart';

// PROFILE
import 'screens/profile_user_screen.dart';
import 'screens/profile_agent_screen.dart';
import 'screens/edit_profile.dart';
import 'screens/profile_picker.dart';
import 'screens/profile_sharing_screen.dart';
import 'screens/profile_accept_invite_screen.dart';
import 'screens/profile_updates_screen.dart';
import 'screens/new_profile_screen.dart';
import 'screens/referral_center_screen.dart';
import 'screens/agent_referrals_screen.dart';

// MEDICAL
import 'screens/meds_screen.dart';
import 'screens/doctors_screen.dart';
import 'screens/doctors_view.dart';
import 'screens/appointments_screen.dart';
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

// GLOBALS
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final AppLinks _appLinks = AppLinks();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _setupNotificationDisplay() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final languageCode = await LanguageService.getEffectiveLanguageCode();
  final channel = AndroidNotificationChannel(
    'vitalink_high_importance',
    languageCode == 'es' ? 'Alertas de VitaLink' : 'VitaLink Alerts',
    description: languageCode == 'es'
        ? 'Alertas importantes de VitaLink y notificaciones de referidos.'
        : 'Important VitaLink alerts and referral notifications.',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
}

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

              _captureProfileShareInvite(message);
              final route = data["route"];
              if (route != null) {
                navigatorKey.currentState?.pushNamed(route);
              }
            },
            child: const Text("Open"),
          ),
        ],
      );
    },
  );
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// 🔥 TAP HANDLER
void _handleNotificationNavigation(RemoteMessage message) {
  debugPrint("📩 TAP DATA: ${message.data}");
}

void _captureProfileShareInvite(RemoteMessage message) {
  final type = message.data["type"]?.toString();
  final inviteCode = message.data["inviteCode"]?.toString().toUpperCase();

  if (type == "profile_share_invite" &&
      inviteCode != null &&
      inviteCode.isNotEmpty) {
    VitaLinkDeepLink.shareCode = inviteCode;
  }
}

Future<void> _setupFCMGlobal() async {
  try {
    final messaging = FirebaseMessaging.instance;

    final token = await messaging.getToken();
    final store = SecureStore();

    if (token != null) {
      final userId = await store.getString("userId");

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
    debugPrint("❌ FCM ERROR: $e");
  }
}

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    await Firebase.initializeApp();
    await LanguageService.load();
    await _setupNotificationDisplay();
    await _setupFCMGlobal();

    // 🔥 DEEP LINK HANDLER (FIXED LOCATION)
    _appLinks.uriLinkStream.listen((uri) {
      final code = uri.queryParameters['code']?.toUpperCase();

      if (uri.host != 'share' && code != null && code.isNotEmpty) {
        VitaLinkDeepLink.code = code;
        debugPrint("🔥 Deep link code received: $code");
      }
    });

    // 🔥 HANDLE TAP WHEN APP IS CLOSED
    Future<void> handleAssistedOnboardingLink(Uri uri) async {
      final onboardingCode =
          (uri.queryParameters['onboard'] ?? uri.queryParameters['onboarding'])
              ?.toUpperCase();

      if (onboardingCode == null || onboardingCode.isEmpty) return;

      VitaLinkDeepLink.onboardingCode = onboardingCode;
      debugPrint("Assisted onboarding code received: $onboardingCode");

      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushNamed('/registration');
      });
    }

    _appLinks.uriLinkStream.listen(handleAssistedOnboardingLink);

    Future<void> handleProfileShareLink(Uri uri) async {
      if (uri.host != 'share') return;

      final shareCode = uri.queryParameters['code']?.toUpperCase();
      if (shareCode == null || shareCode.isEmpty) return;

      VitaLinkDeepLink.shareCode = shareCode;
      debugPrint("Profile share link code received: $shareCode");

      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushNamed('/profile_accept');
      });
    }

    final initialShareUri = await _appLinks.getInitialLink();
    if (initialShareUri != null) {
      await handleAssistedOnboardingLink(initialShareUri);
      await handleProfileShareLink(initialShareUri);
    }

    _appLinks.uriLinkStream.listen(handleProfileShareLink);

    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      _captureProfileShareInvite(initialMessage);
      final route = initialMessage.data["route"];

      if (route != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushNamed(route);
        });
      }
    }

    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    FirebaseMessaging.onMessage.listen((message) {
      showGlobalNotificationPopup(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationNavigation(message);
      _captureProfileShareInvite(message);

      final route = message.data["route"];

      if (route != null) {
        navigatorKey.currentState?.pushNamed(route);
      }
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
    return ValueListenableBuilder<Locale?>(
      valueListenable: LanguageService.localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          theme: ThemeData(
            useMaterial3: false,
            primaryColor: Colors.blue,
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            dialogTheme: const DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          navigatorKey: navigatorKey,
          title: 'VitaLink',
          locale: locale,
          supportedLocales: const [
            Locale('en'),
            Locale('es'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          debugShowCheckedModeBanner: false,
          home: const LandingScreen(),
          builder: (context, child) {
            return SafeArea(
              child: child ?? const SizedBox.shrink(),
            );
          },
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
            '/agent_notes': (context) => const AgentNotesScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/my_agent_user': (context) => const MyAgentUser(),
            '/my_agent_agent': (context) => const MyAgentAgent(),
            '/emergency': (context) => const EmergencyScreen(),
            '/emergency_view': (context) => const EmergencyView(),
            '/my_profile_user': (context) => const ProfileUserScreen(),
            '/my_profile_agent': (context) => const ProfileAgentScreen(),
            '/edit_profile': (context) => const EditProfileScreen(),
            '/profile_picker': (context) => const ProfilePickerScreen(),
            '/profile_sharing': (context) => const ProfileSharingScreen(),
            '/profile_accept': (context) => const ProfileAcceptInviteScreen(),
            '/profile_updates': (context) => const ProfileUpdatesScreen(),
            '/new_profile': (context) => const NewProfileScreen(),
            '/referral_center': (context) => const ReferralCenterScreen(),
            '/agent_referrals': (context) => const AgentReferralsScreen(),
            '/meds': (context) => const MedsScreen(),
            '/doctors': (context) => const DoctorsScreen(),
            '/doctors_view': (context) => const DoctorsView(),
            '/appointments': (context) => const AppointmentsScreen(),
            '/insurance_policies': (context) => const InsurancePoliciesScreen(),
            '/insurance_cards_menu': (context) => const IOSCardScanScreen(),
            '/scan_card': (context) => const ScanCard(),
            '/authorization_form': (context) => const HipaaFormScreen(),
            '/request_reset': (context) => const RequestResetScreen(),
            '/reset_password': (context) => const ResetPasswordScreen(),
            '/agent_request_reset': (context) =>
                const AgentRequestResetScreen(),
            '/agent_reset_password': (context) =>
                const AgentResetPasswordScreen(),
            '/update_app': (context) => const UpdateAppScreen(),
          },
        );
      },
    );
  }
}
