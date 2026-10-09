import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/l10n/app_strings.dart';
import 'package:vitalink/screens/registration_screen.dart';

Widget _registrationWith(Object? arguments,
    {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('es')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    onGenerateRoute: (_) => MaterialPageRoute(
      settings: RouteSettings(arguments: arguments),
      builder: (_) => const RegistrationScreen(),
    ),
  );
}

void main() {
  const en = AppStrings('en');
  const es = AppStrings('es');

  testWidgets('an onboarding link looks up the agent-entered details',
      (tester) async {
    // The test binding answers every HTTP request with 400, so the lookup
    // "fails" and the screen must say so (with the server's message) instead
    // of silently ignoring the link.
    await tester.pumpWidget(_registrationWith({'onboard': 'ABC123'}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Server returned 400'), findsOneWidget);
    expect(find.text(en.assistedOnboardingPromptTitle), findsOneWidget);
  });

  testWidgets('clients can type an onboarding code by hand', (tester) async {
    await tester
        .pumpWidget(_registrationWith(null, locale: const Locale('es')));
    await tester.pumpAndSettle();
    expect(find.text(es.assistedOnboardingPromptTitle), findsOneWidget);

    await tester.tap(find.text(es.loadMyInfo));
    await tester.pump();
    expect(find.text(es.enterOnboardingCode), findsWidgets);
  });

  // Guards against the Aug 25 regression where the app stopped reading the
  // onboard parameter from CRM / agent access / agent report links.
  test('the app still handles onboard= links', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("queryParameters['onboard']"));
    expect(main, contains("'/terms_user'"));
  });
}
