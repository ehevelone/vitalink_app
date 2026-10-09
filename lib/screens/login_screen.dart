import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';

import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/device_id.dart';
import '../services/fcm_token_service.dart';
import '../services/device_security_service.dart';
import '../services/device_transfer_service.dart';
import '../services/transfer_code.dart';
import '../widgets/transfer_code_dialog.dart';
import 'reset_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = true;
  bool _rememberMe = false;
  bool _showPassword = false;

  String? _errorMessage;

  /// Loads the transfer the server already verified at login. The package
  /// stays downloadable by this phone for 6 hours, so a failed attempt can be
  /// retried here or later from Settings without a new code.
  Future<void> _restoreTransferAfterLogin(String code) async {
    while (mounted) {
      try {
        await DeviceTransferService().redeemTransfer(code);
      } on TransferCleanupException {
        // Profiles were imported; only the server cleanup failed.
      } catch (e) {
        if (!mounted) return;
        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(AppStrings.of(context).transferNotLoadedYet),
            content: Text(
              '${e.toString().replaceFirst('Exception: ', '')}\n\n'
              '${AppStrings.of(context).transferRetryHint}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppStrings.of(context).later),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppStrings.of(context).tryAgain),
              ),
            ],
          ),
        );
        if (retry == true) continue;
        return;
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppStrings.of(context).transferCompleteTitle),
          content: Text(
            AppStrings.of(context).transferCompleteBody,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.of(context).continueLabel),
            ),
          ],
        ),
      );
      return;
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLogin();
    });
  }

  Future<void> _initLogin() async {
    final store = SecureStore();

    final remember = await store.getBool("rememberMeUser");

    if (remember == true) {
      final email = await store.getString("savedUserEmail") ?? "";
      final pass = await store.getString("savedUserPassword") ?? "";

      _emailCtrl.text = email;
      _passwordCtrl.text = pass;
      _rememberMe = true;
    }

    setState(() {
      _loading = false;
    });
  }

  Future<String?> _showReplacePopup() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.of(context).newInstallationDetected,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppStrings.of(context).newInstallationBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => Navigator.pop(ctx, "current_installation"),
                child: Text(AppStrings.of(context).thisIsMyCurrentPhone,
                    style: const TextStyle(color: Colors.black)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => Navigator.pop(ctx, "replaced"),
                child: Text(AppStrings.of(context).iCreatedTransferCode,
                    style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => Navigator.pop(ctx, "lost_stolen"),
                child: Text(AppStrings.of(context).itWasLostOrStolen,
                    style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppStrings.of(context).cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login({
    bool replace = false,
    bool auto = false,
    bool recoverInstallation = false,
    bool validateForm = true,
    String replacementReason = "replaced",
    String? transferCode,
  }) async {
    final loginStopwatch = Stopwatch()..start();
    void logStage(String stage) {
      debugPrint(
        "$stage elapsedMs=${loginStopwatch.elapsedMilliseconds} "
        "replace=$replace recovery=$recoverInstallation",
      );
    }

    if (!auto && validateForm) {
      final formState = _formKey.currentState;
      if (formState == null || !formState.validate()) return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    logStage("LOGIN_START");

    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      final password = _passwordCtrl.text.trim();
      final deviceId = await DeviceId.getOrCreate();
      String? fcmToken;
      try {
        fcmToken = await FcmTokenService.getToken();
      } catch (_) {}

      final platform =
          !mounted || Theme.of(context).platform == TargetPlatform.iOS
              ? "ios"
              : "android";

      if (replace || recoverInstallation) {
        logStage("DEVICE_SWITCH_REQUEST_START");
      }
      final res = await ApiService.loginUser(
        email: email,
        password: password,
        platform: platform,
        deviceId: deviceId,
        fcmToken: fcmToken,
        recoverInstallation: recoverInstallation,
        replace: replace,
        replacementReason: replacementReason,
        transferCode: transferCode == null
            ? null
            : TransferCode.parse(transferCode).serverCode,
      );
      logStage("LOGIN_RESPONSE");

      if (!mounted) return;

      if (res["success"] == true) {
        final user = res["user"];
        final store = SecureStore();
        final nextUserId = user["id"].toString();
        await store.clearAuth();
        await store.setString('profileOwnerUserId', nextUserId);
        await DeviceSecurityService.clearLocalRevocationForReplacement();

        logStage("SESSION_SAVE_START");
        await AppState.setLoggedIn(true);
        await AppState.setRole("user");
        await AppState.setEmail(user["email"]);

        // ✅ FIX — STORE AS STRING
        await store.setString("userId", nextUserId);

        await store.setString("userEmail", user["email"]);

        final sessionToken = user["session_token"]?.toString() ?? "";
        if (sessionToken.isNotEmpty) {
          await store.setString("userSessionToken", sessionToken);
        } else {
          await store.remove("userSessionToken");
        }

        if (_rememberMe) {
          await store.setBool("rememberMeUser", true);
          await store.setString("savedUserEmail", email);
          await store.setString("savedUserPassword", password);
        } else {
          await store.setBool("rememberMeUser", false);
          await store.remove("savedUserEmail");
          await store.remove("savedUserPassword");
        }
        logStage("SESSION_SAVE_COMPLETE");

        try {
          logStage("DEVICE_TOKEN_REGISTER_START");
          final fcm = await FcmTokenService.getToken();
          if (fcm != null) {
            final userId = await store.getString("userId");
            if (userId != null) {
              await ApiService.registerDeviceToken(
                userId: userId,
                fcmToken: fcm,
              );
            }
          }
          logStage("DEVICE_TOKEN_REGISTER_COMPLETE");
        } catch (error) {
          debugPrint(
            "DEVICE_TOKEN_REGISTER_FAILED errorType=${error.runtimeType}",
          );
        }

        if (!mounted) return;

        if (replace && replacementReason == 'replaced') {
          if (transferCode != null) {
            await _restoreTransferAfterLogin(transferCode);
          }
          if (!mounted) return;
        }
        logStage("NAVIGATION_START");
        Navigator.pushReplacementNamed(context, "/logo");
      } else if (res["error"] == "DEVICE_ACTIVE" && replace == false) {
        logStage("DEVICE_CONFLICT_DETECTED");
        final choice = await _showReplacePopup();
        if (choice != null) logStage("DEVICE_SWITCH_CONFIRMED");
        if (choice == "lost_stolen") {
          if (!mounted) return;
          final lostOrStolen = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(AppStrings.of(context).disableOldDeviceTitle),
              content: Text(
                AppStrings.of(context).disableOldDeviceBody,
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(AppStrings.of(context).cancel)),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, "lost"),
                    child: Text(AppStrings.of(context).lost)),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, "stolen"),
                    child: Text(AppStrings.of(context).stolen)),
              ],
            ),
          );
          if (lostOrStolen != null) {
            await _login(
              replace: true,
              validateForm: false,
              replacementReason: lostOrStolen,
            );
          }
        } else if (choice == "current_installation") {
          await _login(
            recoverInstallation: true,
            validateForm: false,
          );
        } else if (choice == "replaced") {
          if (!mounted) return;
          // Collect and check the code before the old phone is switched off.
          final code = await showTransferCodeDialog(context);
          if (code != null) {
            await _login(
              replace: true,
              validateForm: false,
              replacementReason: "replaced",
              transferCode: code,
            );
          }
        }
      } else if (res["error"] == "DEVICE_REVOKED") {
        await DeviceSecurityService.disableCurrentDevice(
          reason: res["reason"]?.toString(),
        );
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
            context, '/device_disabled', (_) => false);
      } else if (res["error"] == "TRANSFER_CODE_INVALID") {
        setState(() {
          _errorMessage = res["message"]?.toString() ??
              AppStrings.of(context).transferCodeDoesNotMatch;
        });
      } else if (res["error"] == "TRANSFER_REQUIRED") {
        setState(() {
          _errorMessage = AppStrings.of(context).transferRequired;
        });
      } else if (res["error"] == "INSTALLATION_RECOVERY_NOT_VERIFIED") {
        setState(() {
          _errorMessage =
              AppStrings.of(context).installationRecoveryNotVerified;
        });
      } else {
        final store = SecureStore();

        if (auto) {
          await store.remove("savedUserPassword");
          await store.setBool("rememberMeUser", false);
        }

        if (!mounted) return;
        String msg = AppStrings.of(context).loginFailed;

        if (res["httpStatus"] == 401) {
          msg = AppStrings.of(context).incorrectPassword;
        } else if (res["httpStatus"] == 404) {
          msg = AppStrings.of(context).accountNotFound;
        } else if (res["error"] != null) {
          msg = res["error"];
        }

        setState(() {
          _errorMessage = msg;
        });
      }
    } catch (error) {
      debugPrint('LOGIN_LOCAL_FAILURE type=${error.runtimeType}');
      if (mounted) {
        setState(() {
          _errorMessage = AppStrings.of(context).loginCouldNotFinish;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _goToReset() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(
          emailOrPhone: _emailCtrl.text.trim(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).userLogin)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _emailCtrl,
                onChanged: (_) => _clearError(),
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).email),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterEmail
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                onChanged: (_) => _clearError(),
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).password,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).enterPassword
                    : null,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _goToReset,
                  child: Text(AppStrings.of(context).forgotPassword),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                title: Text(AppStrings.of(context).rememberMe),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _login(),
                child: Text(AppStrings.of(context).login),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
