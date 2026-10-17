import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalink/l10n/app_strings.dart';
import 'package:vitalink/l10n/screen_strings.dart';
import 'package:vitalink/screens/my_agent_user.dart';
import 'package:vitalink/screens/settings_screen.dart';
import 'package:vitalink/widgets/agent_preferences.dart';

const strings = AppStrings('en');

class FakeAccess {
  FakeAccess({this.prospect = false, this.connected = true});
  final bool prospect;
  final bool connected;
  bool failSave = false;
  final calls = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> load(String userId) async => {
        'success': true,
        'access': {
          'agentId': connected ? 9 : null,
          'relationshipStatus':
              prospect ? 'confirmed_prospect' : 'confirmed_client',
          'canMessage': true,
          'prospectConsents': {
            'medicare': {'status': 'pending'},
            'life': {'status': 'granted'},
          },
          'prospectOptions': {
            'medicare': {'text': 'Server-provided Medicare consent'},
          },
        },
      };

  Future<Map<String, dynamic>> update({
    required String userId,
    required String action,
    Map<String, dynamic> values = const {},
  }) async {
    calls.add({'userId': userId, 'action': action, ...values});
    if (failSave) throw Exception('offline');
    return {'success': true};
  }
}

Future<void> open(WidgetTester tester, FakeAccess fake) async {
  await tester.binding.setSurfaceSize(const Size(500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: SingleChildScrollView(
            child: AgentPreferences(
      loadAccess: fake.load,
      updateAccess: fake.update,
    ))),
    routes: {
      '/account_access': (_) => const Scaffold(body: Text('Access setup'))
    },
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues(
        {'userId': '7', 'deviceId': 'test-device'});
    PackageInfo.setMockInitialValues(
        appName: 'VitaLink',
        packageName: 'app.vitalink',
        version: '2.0.29',
        buildNumber: '122',
        buildSignature: '');
  });

  testWidgets('client messages retain consent and device audit values',
      (tester) async {
    final fake = FakeAccess();
    await open(tester, fake);
    expect(find.text(strings.messagesFromMyAgent), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await tester.tap(find.text(strings.turnOffMessages));
    await tester.pumpAndSettle();
    expect(fake.calls.single, containsPair('action', 'messaging_consent'));
    expect(fake.calls.single, containsPair('userId', '7'));
    expect(fake.calls.single, containsPair('messagingConsent', false));
    expect(fake.calls.single, containsPair('userAttestation', true));
    expect(fake.calls.single, containsPair('deviceId', 'test-device'));
    expect(fake.calls.single['platform'], isNotEmpty);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
  });

  testWidgets('failed consent save keeps the prior value and allows retry',
      (tester) async {
    final fake = FakeAccess()..failSave = true;
    await open(tester, fake);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.turnOffMessages));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    expect(find.text(strings.unableToUpdateConsent), findsOneWidget);
    fake.failSave = false;
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.turnOffMessages));
    await tester.pumpAndSettle();
    expect(fake.calls, hasLength(2));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
  });

  testWidgets('cancel and back keep messages on; enabling needs no confirmation',
      (tester) async {
    final fake = FakeAccess();
    await open(tester, fake);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.keepMessagesOn));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.turnOffMessages));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.calls, hasLength(2));
    expect(fake.calls.last, containsPair('messagingConsent', true));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
  });

  testWidgets('prospect opt-in requires the existing consent confirmation',
      (tester) async {
    final fake = FakeAccess(prospect: true);
    await open(tester, fake);
    final medicare =
        find.widgetWithText(SwitchListTile, strings.medicareMessages);
    await tester.tap(medicare);
    await tester.pumpAndSettle();
    expect(find.text('Server-provided Medicare consent'), findsOneWidget);
    await tester.tap(find.text(strings.cancel));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    await tester.tap(medicare);
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.iAgree));
    await tester.pumpAndSettle();
    expect(fake.calls.single,
        containsPair('action', 'prospect_marketing_consent'));
    expect(fake.calls.single, containsPair('category', 'medicare'));
    expect(fake.calls.single, containsPair('granted', true));
    expect(tester.widget<SwitchListTile>(medicare).value, isTrue);
  });

  testWidgets('disconnect cancels safely and confirms into access setup',
      (tester) async {
    final fake = FakeAccess();
    await open(tester, fake);
    await tester.tap(find.text(strings.changeOrDisconnectAgent));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.keepMyCurrentAgent));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    await tester.tap(find.text(strings.changeOrDisconnectAgent));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.disconnectAndLock));
    await tester.pumpAndSettle();
    expect(fake.calls.single, containsPair('action', 'disconnect'));
    expect(fake.calls.single, containsPair('deviceId', 'test-device'));
    expect(find.text('Access setup'), findsOneWidget);
  });

  testWidgets('unconnected accounts have no agent preference controls',
      (tester) async {
    await open(tester, FakeAccess(connected: false));
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text(strings.changeOrDisconnectAgent), findsNothing);
  });

  testWidgets('Settings owns the controls and My Agent no longer shows them',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'userId': '7'});
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(AgentPreferences), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byType(AgentPreferences), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: MyAgentUser()));
    await tester.pumpAndSettle();
    expect(find.byType(AgentPreferences), findsNothing);
    expect(find.text(strings.messagesFromMyAgent), findsNothing);
    expect(find.text(strings.changeOrDisconnectAgent), findsNothing);
  });
}
