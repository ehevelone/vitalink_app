// lib/main.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
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
import 'services/device_security_service.dart';
import 'services/device_id.dart';
import 'services/fcm_token_service.dart';
import 'l10n/app_strings.dart';
import 'services/language_service.dart';
import 'services/notification_routes.dart';
import 'widgets/app_update_gate.dart';

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
import 'screens/settings_screen.dart';
import 'screens/account_access_screen.dart';
import 'screens/device_disabled_screen.dart';
import 'screens/prospect_contact_request_screen.dart';

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
String? _lastHandledUri;
DateTime? _lastHandledUriAt;
final Set<String> _streamHandledUris = <String>{};

const AndroidNotificationChannel vitalinkNotificationChannel =
    AndroidNotificationChannel(
  'vitalink_high_importance',
  'VitaLink Alerts',
  description: 'Important VitaLink alerts and referral notifications.',
  importance: Importance.high,
);

@visibleForTesting
InitializationSettings notificationInitializationSettings() {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwinSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  return const InitializationSettings(
    android: androidSettings,
    iOS: darwinSettings,
  );
}

Future<void> _setupNotificationDisplay() async {
  final initSettings = notificationInitializationSettings();

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(vitalinkNotificationChannel);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: false,
    badge: true,
    sound: true,
  );
}

@visibleForTesting
void navigateWhenReady(String route, {Object? arguments}) {
  final navigator = navigatorKey.currentState;
  if (navigator != null) {
    navigator.pushNamed(route, arguments: arguments);
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    navigatorKey.currentState?.pushNamed(route, arguments: arguments);
  });
  WidgetsBinding.instance.scheduleFrame();
}

@visibleForTesting
void resetIncomingUriDeduplication() {
  _lastHandledUri = null;
  _lastHandledUriAt = null;
  _streamHandledUris.clear();
}

@visibleForTesting
bool handleIncomingUri(
  Uri uri, {
  DateTime? handledAt,
  bool isInitialLinkFallback = false,
  void Function(String route, {Object? arguments})? navigate,
}) {
  final now = handledAt ?? DateTime.now();
  final uriKey = uri.toString();
  if (isInitialLinkFallback && _streamHandledUris.contains(uriKey)) {
    return false;
  }
  if (_lastHandledUri == uriKey &&
      _lastHandledUriAt != null &&
      now.difference(_lastHandledUriAt!).abs() < const Duration(seconds: 3)) {
    return false;
  }
  if (!isInitialLinkFallback) {
    _streamHandledUris.add(uriKey);
  }
  _lastHandledUri = uriKey;
  _lastHandledUriAt = now;

  final navigateTo = navigate ?? navigateWhenReady;
  final rawCode = uri.queryParameters['code']?.trim();
  final onboardingCode =
      (uri.queryParameters['onboard'] ?? uri.queryParameters['onboarding'])
          ?.trim()
          .toUpperCase();

  if (uri.host == 'share' && rawCode != null && rawCode.isNotEmpty) {
    VitaLinkDeepLink.shareCode = rawCode;
    navigateTo('/profile_accept');
  } else if (rawCode != null && rawCode.isNotEmpty) {
    VitaLinkDeepLink.code = rawCode.toUpperCase();
  }

  if (onboardingCode != null && onboardingCode.isNotEmpty) {
    VitaLinkDeepLink.onboardingCode = onboardingCode;
    navigateTo('/terms_user', arguments: {'onboard': onboardingCode});
  }
  return true;
}

// 🔥 POPUP
bool _notificationPopupOpen = false;

// One handler for every screen (clients and agents). The client and agent
// menus used to add their own listeners too, which could show the same
// notification twice; this keeps the agent menu's dark style instead.
void showGlobalNotificationPopup(RemoteMessage message) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || _notificationPopupOpen) return;

  final data = message.data;
  final strings = AppStrings.of(ctx);
  _notificationPopupOpen = true;

  showDialog(
    context: ctx,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          data["title"] ??
              message.notification?.title ??
              strings.newNotification,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          data["body"] ??
              message.notification?.body ??
              strings.newNotificationBody,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              strings.dismiss,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(context);

              _captureProfileShareInvite(message);
              final route = data["route"];
              if (_isKnownNotificationRoute(route)) {
                navigatorKey.currentState?.pushNamed(route, arguments: data);
              }
            },
            child: Text(
              strings.openLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    },
  ).whenComplete(() => _notificationPopupOpen = false);
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// 🔥 TAP HANDLER
void _handleNotificationNavigation(RemoteMessage message) {
  debugPrint("Notification opened");
}

void _captureProfileShareInvite(RemoteMessage message) {
  final type = message.data["type"]?.toString();
  final inviteCode = message.data["inviteCode"]?.toString();

  if (type == "profile_share_invite" &&
      inviteCode != null &&
      inviteCode.isNotEmpty) {
    VitaLinkDeepLink.shareCode = inviteCode;
  }
}

bool _isKnownNotificationRoute(dynamic route) =>
    isKnownNotificationRoute(route);

Future<bool> _revocationTargetsCurrentDevice(RemoteMessage message) async {
  final targetUserId = message.data['userId']?.toString() ?? '';
  final targetDeviceId = message.data['deviceId']?.toString() ?? '';
  if (targetUserId.isEmpty || targetDeviceId.isEmpty) return false;

  final store = SecureStore();
  final currentUserId = await store.getString('userId') ?? '';
  final currentDeviceId = await DeviceId.getOrCreate();
  return targetUserId == currentUserId && targetDeviceId == currentDeviceId;
}

Future<void> _setupFCMGlobal() async {
  try {
    final messaging = FirebaseMessaging.instance;

    final token = await FcmTokenService.getToken();
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
        try {
          await ApiService.registerDeviceToken(
            userId: userId,
            fcmToken: newToken,
          );
        } catch (error) {
          debugPrint('FCM TOKEN REFRESH REGISTRATION FAILED: $error');
        }
      }
    });
  } catch (e) {
    debugPrint("❌ FCM ERROR: $e");
  }
}

Future<void> main() async {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  WidgetsFlutterBinding.ensureInitialized();

  await runZonedGuarded(() async {
    try {
      await LanguageService.load().timeout(const Duration(seconds: 1));
    } catch (_) {}

    try {
      _appLinks.uriLinkStream.listen(handleIncomingUri);
    } catch (error) {
      debugPrint('DEEP LINK LISTENER INITIALIZATION FAILED: $error');
    }

    // Paint the app before optional platform services initialize. A plugin
    // failure must never leave a fresh install on the native white screen.
    runApp(const VitaLinkApp());

    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } catch (error) {
      debugPrint('SYSTEM UI INITIALIZATION FAILED: $error');
    }

    var firebaseReady = false;
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (error) {
      debugPrint('FIREBASE INITIALIZATION FAILED: $error');
    }

    if (firebaseReady) {
      try {
        await _setupNotificationDisplay();
      } catch (error) {
        debugPrint('NOTIFICATION DISPLAY INITIALIZATION FAILED: $error');
      }
    }

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        handleIncomingUri(initialUri, isInitialLinkFallback: true);
      }
    } catch (error) {
      debugPrint('INITIAL LINK LOOKUP FAILED: $error');
    }

    if (!firebaseReady) return;

    RemoteMessage? initialMessage;
    try {
      initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    } catch (error) {
      debugPrint('INITIAL NOTIFICATION LOOKUP FAILED: $error');
    }

    if (initialMessage != null) {
      final message = initialMessage;
      _captureProfileShareInvite(message);
      final route = message.data["route"];

      if (_isKnownNotificationRoute(route)) {
        navigateWhenReady(route, arguments: message.data);
      }
    }

    try {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      FirebaseMessaging.onMessage.listen((message) async {
        if (message.data['type'] == 'device_revoked') {
          if (!await _revocationTargetsCurrentDevice(message)) return;
          await DeviceSecurityService.disableCurrentDevice(
            reason: message.data['reason']?.toString(),
          );
          navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/device_disabled',
            (route) => false,
          );
          return;
        }
        showGlobalNotificationPopup(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleNotificationNavigation(message);
        _captureProfileShareInvite(message);

        final route = message.data["route"];

        if (_isKnownNotificationRoute(route)) {
          navigateWhenReady(route, arguments: message.data);
        }
      });
    } catch (error) {
      debugPrint('FIREBASE MESSAGE LISTENER INITIALIZATION FAILED: $error');
    }

    // Token lookup and registration can be slow on poor connections; never
    // hold the first screen for them.
    unawaited(_setupFCMGlobal());
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
    // Rebuild the whole app when the Settings language picker changes.
    return ValueListenableBuilder<Locale?>(
      valueListenable: LanguageService.localeNotifier,
      builder: (context, locale, _) => MaterialApp(
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
          return AppUpdateGate(
            navigatorKey: navigatorKey,
            child: SafeArea(
              child: child ?? const SizedBox.shrink(),
            ),
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
          '/account_access': (context) => const AccountAccessScreen(),
          '/device_disabled': (context) => const DeviceDisabledScreen(),
          '/prospect_contact_request': (context) =>
              const ProspectContactRequestScreen(),
          '/logo': (context) => const LogoScreen(),
          '/menu': (context) => const MenuScreen(),
          '/agent_menu': (context) => const AgentMenuScreen(),
          '/agent_clients': (context) => const AgentClientsScreen(),
          '/agent_notes': (context) => const AgentNotesScreen(),
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
          '/settings': (context) => const SettingsScreen(),
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
          '/agent_request_reset': (context) => const AgentRequestResetScreen(),
          '/agent_reset_password': (context) =>
              const AgentResetPasswordScreen(),
          '/update_app': (context) => const UpdateAppScreen(),
        },
      ),
    );
  }
}
