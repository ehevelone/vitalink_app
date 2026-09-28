import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/screens/registration_screen.dart';

void main() {
  testWidgets('client registration offers assisted onboarding before activation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RegistrationScreen()),
    );

    expect(find.text('Did your agent already start your registration?'),
        findsOneWidget);
    expect(find.text('Onboarding Code'), findsOneWidget);
    expect(find.text('Load My Info'), findsOneWidget);
    expect(find.text('Activation Code'), findsOneWidget);
  });
}
