import 'dart:async';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/secure_store.dart';
import '../services/fcm_token_service.dart';
import '../services/app_state.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';

class AgentMenuScreen extends StatefulWidget {
  const AgentMenuScreen({super.key});

  @override
  State<AgentMenuScreen> createState() => _AgentMenuScreenState();
}

class _AgentMenuScreenState extends State<AgentMenuScreen> {
  bool _loading = true;
  String agentName = "Agent";
  bool _showRegisterUserAccount = false;
  bool _openingUserRegistration = false;
  bool _notificationPermissionDialogShown = false;
  StreamSubscription<String>? _tokenSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupAgentNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAgentAgreement());
  }

  Future<void> _checkAgentAgreement() async {
    final store = SecureStore();
    final agentId = int.tryParse(await store.getString('agentId') ?? '');
    if (agentId == null) return;
    final status = await ApiService.getAgentAgreement(agentId);
    if (!mounted || status['success'] != true || status['current'] == true) {
      return;
    }

    var checked = false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).agentAgreementUpdate),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.of(context).agentResponsibilitiesBody,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  onChanged: (value) =>
                      setDialogState(() => checked = value ?? false),
                  title:
                      Text(AppStrings.of(context).agreeAgentResponsibilities),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: Text(AppStrings.of(context).accept),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) await ApiService.acceptAgentAgreement(agentId);
  }

  // Agents switch the app language here (Settings is client-only). The
  // device is re-registered so notifications follow the new language.
  Future<void> _chooseLanguage() async {
    final strings = AppStrings.of(context);
    final current = await LanguageService.getLanguageCode();
    if (!mounted) return;
    final labels = {
      'system': strings.usePhoneLanguage,
      'en': strings.english,
      'es': 'Español (${strings.spanish})',
    };
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(strings.language),
        children: [
          for (final option in LanguageService.supportedLanguages)
            ListTile(
              leading: Icon(option.code == current
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(labels[option.code] ?? option.label),
              onTap: () => Navigator.pop(ctx, option.code),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == current) return;
    await LanguageService.setLanguageCode(chosen);
    await _registerAgentToken();
  }

  Future<void> _registerAgentToken() async {
    try {
      final store = SecureStore();
      final agentIdText = await store.getString("agentId");
      final agentId = int.tryParse(agentIdText ?? "");
      if (agentId == null || agentId <= 0) return;

      final token = await FcmTokenService.getToken();
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
          title: Text(
            AppStrings.of(context).allowNotifications,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            AppStrings.of(context).agentNotificationsNeeded,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              child: Text(AppStrings.of(context).later),
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
              child: Text(AppStrings.of(context).openSettings),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _loadData() async {
    final store = SecureStore();
    final storedName = await store.getString("agentName");
    final agentEmail = await store.getString("agentEmail") ?? "";
    final locallyCreated =
        await store.getBool("agentUserAccountCreated") == true;
    var userAccountExists = locallyCreated;

    if (agentEmail.isNotEmpty && !locallyCreated) {
      try {
        final codeResult = await ApiService.getAgentPromoCode(agentEmail);
        if (codeResult['success'] == true) {
          final code = codeResult['promoCode']?.toString() ?? "";
          if (code.isNotEmpty) {
            await store.setString("agentPromoCode", code);
          }
          userAccountExists = codeResult['userAccountExists'] == true;
          if (userAccountExists) {
            await store.setBool("agentUserAccountCreated", true);
          }
        }
      } catch (e) {
        debugPrint("Agent user-account status error: $e");
      }
    }

    if (!mounted) return;

    setState(() {
      if (storedName != null && storedName.isNotEmpty) {
        agentName = storedName;
      } else {
        agentName = "Agent";
      }

      _showRegisterUserAccount = !userAccountExists;
      _loading = false;
    });
  }

  Future<void> _openUserRegistration() async {
    if (_openingUserRegistration) return;
    setState(() => _openingUserRegistration = true);

    try {
      final store = SecureStore();
      final email = await store.getString("agentEmail") ?? "";
      var name = await store.getString("agentName") ?? "";
      var phone = await store.getString("agentPhone") ?? "";
      var code = await store.getString("agentPromoCode") ?? "";
      final password = await store.getString("savedAgentPassword") ?? "";

      if (email.isNotEmpty) {
        final results = await Future.wait([
          ApiService.getAgentProfile(email: email),
          if (code.isEmpty) ApiService.getAgentPromoCode(email),
        ]);

        final profileResult = results.first;
        if (profileResult['success'] == true && profileResult['agent'] is Map) {
          final agent = profileResult['agent'] as Map;
          name = agent['name']?.toString() ?? name;
          phone = agent['phone']?.toString() ?? phone;
        }

        if (code.isEmpty && results.length > 1) {
          final codeResult = results[1];
          code = codeResult['promoCode']?.toString() ?? "";
          if (code.isNotEmpty) {
            await store.setString("agentPromoCode", code);
          }
        }
      }

      if (!mounted) return;

      if (code.isEmpty) {
        _showSetupMessage(
          AppStrings.of(context).agentCodeNeeded,
          AppStrings.of(context).couldntLoadAgentCode,
        );
        return;
      }

      await Navigator.pushNamed(
        context,
        '/registration',
        arguments: {
          'fromAgentAccount': true,
          'code': code,
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
        },
      );

      if (!mounted) return;
      await _loadData();
    } finally {
      if (mounted) {
        setState(() => _openingUserRegistration = false);
      }
    }
  }

  void _showSetupMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7ED6F8),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
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
    _tokenSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: Text(
          AppStrings.of(context).welcomeAgent(agentName == 'Agent'
              ? AppStrings.of(context).agentWord
              : agentName),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: AppStrings.of(context).language,
            icon: const Icon(Icons.language),
            onPressed: _chooseLanguage,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset(
              "assets/images/app_icon_big.png",
              height: 32,
              cacheHeight: 96,
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
                  cacheWidth: 1024,
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
                            _item(Icons.badge, AppStrings.of(context).myAgent,
                                '/my_agent_agent'),
                            _item(
                                Icons.person,
                                AppStrings.of(context).myProfile,
                                '/my_profile_agent'),
                            _item(
                              Icons.document_scanner,
                              AppStrings.of(context).businessCardScanner,
                              '/my_profile_agent',
                              arguments: {'autoScan': true},
                            ),

                            // NEW BUTTON
                            _item(
                                Icons.groups,
                                AppStrings.of(context).myClients,
                                '/agent_clients'),
                            _item(
                                Icons.favorite,
                                AppStrings.of(context).referralCenter,
                                '/agent_referrals'),
                            _item(
                                Icons.task_alt,
                                AppStrings.of(context).notesTasks,
                                '/agent_notes'),
                            _item(Icons.medical_information,
                                AppStrings.of(context).medications, '/meds'),
                            _item(Icons.people, AppStrings.of(context).doctors,
                                '/doctors'),
                            _item(
                                Icons.credit_card,
                                AppStrings.of(context).insuranceCards,
                                '/insurance_cards_menu'),
                            _item(
                                Icons.policy,
                                AppStrings.of(context).insurancePolicies,
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
                              if (_showRegisterUserAccount) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: _openingUserRegistration
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.person_add_alt_1),
                                    label: Text(
                                      AppStrings.of(context)
                                          .registerUserAccount,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: _openingUserRegistration
                                        ? null
                                        : _openUserRegistration,
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
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
                                  label: Text(
                                    AppStrings.of(context).emergencyInfo,
                                    style: const TextStyle(fontSize: 17),
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
                                  label: Text(
                                    AppStrings.of(context).logOut,
                                    style: const TextStyle(fontSize: 17),
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
