import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/screens/login_screen.dart';
import 'package:vitalink/screens/logo_screen.dart';

Widget agentLogoApp() {
  return MaterialApp(
    onGenerateInitialRoutes: (_) => [
      MaterialPageRoute<void>(
        settings: const RouteSettings(arguments: {
          'justLoggedIn': true,
          'role': 'agent',
          'agentSessionToken': 'test-session',
        }),
        builder: (_) => const LogoScreen(),
      ),
    ],
    routes: {
      '/agent_menu': (_) => const Scaffold(body: Text('Agent menu ready')),
      '/emergency': (_) => const Scaffold(body: Text('Emergency info ready')),
    },
  );
}

void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
      'user login leaves its initial spinner when storage is unavailable',
      (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump(const Duration(seconds: 7));

    expect(find.text('User Login'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('agent logo keeps Emergency available before routing',
      (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(agentLogoApp());
    expect(find.text('EMERGENCY'), findsOneWidget);

    await tester.tap(find.text('EMERGENCY'));
    await tester.pumpAndSettle();
    expect(find.text('Emergency info ready'), findsOneWidget);
  });

  testWidgets('fresh agent login continues from logo to agent menu',
      (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(agentLogoApp());
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Agent menu ready'), findsOneWidget);
  });
}
