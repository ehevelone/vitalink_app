import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/screens/meds_screen.dart';

void main() {
  test('a supplement keeps its type, serving size and ingredients', () {
    final saved = Medication(
      name: 'Ginger Root',
      itemType: 'supplement',
      servingSize: '3 capsules',
      activeIngredients: ['Ginger Root Extract - 700 mg'],
      otherIngredients: ['Gelatin'],
    );
    final loaded = Medication.fromJson(
      jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>,
    );
    expect(loaded.itemType, 'supplement');
    expect(loaded.isSupplementOrOtc, isTrue);
    expect(loaded.servingSize, '3 capsules');
    expect(loaded.activeIngredients, ['Ginger Root Extract - 700 mg']);
    expect(loaded.otherIngredients, ['Gelatin']);
  });

  test('medications saved before supplements existed load as prescriptions',
      () {
    final old = Medication.fromJson({'name': 'Lisinopril', 'dose': '10 mg'});
    expect(old.itemType, 'prescription');
    expect(old.isSupplementOrOtc, isFalse);
  });

  testWidgets('the meds screen separates prescriptions from supplements',
      (tester) async {
    final profile = Profile(
      id: '00000000-0000-4000-8000-000000000001',
      fullName: 'Pat Client',
      meds: [
        Medication(name: 'Lisinopril', dose: '10 mg'),
        Medication(
          name: 'Ginger Root',
          itemType: 'supplement',
          servingSize: '3 capsules',
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'userId': '42',
      'userSessionToken': 'session',
      'profiles_json_user_42': jsonEncode([profile.toJson()]),
    });

    await tester.pumpWidget(const MaterialApp(home: MedsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Prescriptions'), findsOneWidget);
    expect(find.text('Supplements & OTC'), findsOneWidget);
    expect(find.text('Lisinopril'), findsOneWidget);
    expect(find.text('Ginger Root'), findsOneWidget);
    expect(find.textContaining('Serving: 3 capsules'), findsOneWidget);
  });

  // The label reader decides prescription vs supplement; the app must not
  // ask the client (owner decision, Oct 2026).
  test('scanning never asks the client what kind of item it is', () {
    final meds = File('lib/screens/meds_screen.dart').readAsStringSync();
    expect(meds, isNot(contains('What are you adding?')));
  });
}
