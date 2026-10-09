import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalink/l10n/app_strings.dart';
import 'package:vitalink/screens/device_disabled_screen.dart';
import 'package:vitalink/screens/landing_screen.dart';
import 'package:vitalink/widgets/password_rules.dart';
import 'package:vitalink/widgets/transfer_code_dialog.dart';

Widget _inLocale(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

void main() {
  const es = AppStrings('es');
  const en = AppStrings('en');

  testWidgets('the landing screen shows Spanish when Spanish is selected',
      (tester) async {
    await tester
        .pumpWidget(_inLocale(const Locale('es'), const LandingScreen()));
    expect(find.text(es.loginToYourAccount), findsOneWidget);
    expect(find.text(en.loginToYourAccount), findsNothing);
  });

  testWidgets('the landing screen stays English by default', (tester) async {
    await tester
        .pumpWidget(_inLocale(const Locale('en'), const LandingScreen()));
    expect(find.text(en.loginToYourAccount), findsOneWidget);
  });

  testWidgets('password rules follow the selected language', (tester) async {
    await tester.pumpWidget(_inLocale(
      const Locale('es'),
      Scaffold(body: PasswordRules(controller: TextEditingController())),
    ));
    expect(find.textContaining(es.passwordMinLength), findsOneWidget);
  });

  testWidgets('the transfer code box is in Spanish, including its error',
      (tester) async {
    await tester.pumpWidget(_inLocale(
      const Locale('es'),
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showTransferCodeDialog(context),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(es.enterYourTransferCode), findsOneWidget);
    expect(find.text(es.transferCodeInstructions), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ABC');
    await tester.tap(find.text(es.continueLabel));
    await tester.pump();
    expect(find.text(es.transferCodeWrongLength), findsOneWidget);
  });

  testWidgets('the disabled-device screen is in Spanish', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'deviceRevocationReason': 'replaced'});
    await tester.pumpWidget(
      _inLocale(const Locale('es'), const DeviceDisabledScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text(es.deviceDisabledTitle), findsOneWidget);
    expect(find.text(es.deviceMovedBody), findsOneWidget);
    expect(find.text(es.returnToLogin), findsOneWidget);
  });

  // Guards against an older copy of main.dart being pasted over the current
  // one again (that is how Spanish was lost on Aug 25).
  test('the Settings language picker is wired into the app', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('LanguageService.localeNotifier'));
    expect(main, contains("Locale('es')"));
    expect(main, contains('GlobalMaterialLocalizations.delegate'));
  });

  test('screens that were translated still use the Spanish wording', () {
    const translated = [
      'lib/screens/emergency_screen.dart',
      'lib/screens/emergency_view.dart',
      'lib/screens/hipaa_form_screen.dart',
      'lib/screens/landing_screen.dart',
      'lib/screens/login_screen.dart',
      'lib/screens/menu_screen.dart',
      'lib/screens/qr_screen.dart',
      'lib/screens/registration_screen.dart',
      'lib/screens/request_reset_screen.dart',
      'lib/screens/reset_password_screen.dart',
      'lib/screens/settings_screen.dart',
      'lib/widgets/password_rules.dart',
      'lib/widgets/transfer_code_dialog.dart',
      'lib/screens/device_disabled_screen.dart',
    ];
    for (final path in translated) {
      expect(File(path).readAsStringSync(), contains('AppStrings.of('),
          reason: '$path lost its Spanish wording');
    }
  });
}
