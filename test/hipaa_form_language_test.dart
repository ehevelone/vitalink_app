import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalink/l10n/app_strings.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/screens/hipaa_form_screen.dart';

Future<void> _pumpForm(WidgetTester tester, Locale locale) async {
  final profile = Profile(
    id: '00000000-0000-4000-8000-000000000001',
    fullName: 'Pat Client',
  );
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({
    'userId': '42',
    'userSessionToken': 'session',
    'profiles_json_user_42': jsonEncode([profile.toJson()]),
  });
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('es')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const HipaaFormScreen(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a Spanish client reads the authorization in Spanish',
      (tester) async {
    await _pumpForm(tester, const Locale('es'));
    expect(find.textContaining('AUTORIZACIÓN HIPAA'), findsOneWidget);
    expect(find.textContaining('HIPAA AUTHORIZATION'), findsNothing);
    expect(find.text(const AppStrings('es').signSendMyInformation),
        findsOneWidget);
  });

  testWidgets('an English client reads the same English text as before',
      (tester) async {
    await _pumpForm(tester, const Locale('en'));
    expect(find.textContaining('HIPAA AUTHORIZATION'), findsOneWidget);
  });

  test('the English authorization wording is unchanged', () {
    const en = AppStrings('en');
    final text = en.hipaaAuthorizationText;
    expect(
        text,
        startsWith('HIPAA AUTHORIZATION & MEDICARE SCOPE OF APPOINTMENT\n\n'
            'By signing below, I authorize my licensed insurance agent'));
    expect(text, contains('This authorization expires one (1) year'));
    expect(
        text,
        contains(
            'This Scope of Appointment remains valid for twelve (12) months'));
  });

  test('Spanish signers send the agent the signed original and a labeled copy',
      () {
    final screen =
        File('lib/screens/hipaa_form_screen.dart').readAsStringSync();
    expect(screen, contains('HIPAA_SOA_Authorization_Signed_Spanish.pdf'));
    expect(screen, contains('English_Translation_For_Agent_Reference.pdf'));
    expect(screen, contains('This is not the signed'));
  });
}
