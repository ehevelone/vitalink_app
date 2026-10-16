import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/main.dart';

void main() {
  testWidgets('navigation requested after first frame completes on next pump', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
        routes: {
          '/destination': (_) => const Scaffold(body: Text('destination')),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(navigatorKey.currentState, isNotNull);

    navigateWhenReady('/destination');
    expect(navigatorKey.currentState!.canPop(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('destination'), findsOneWidget);
  });
}
