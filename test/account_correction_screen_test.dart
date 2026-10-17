import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/screens/account_correction_screen.dart';

class FakeCorrectionApi implements AccountCorrectionApi {
  FakeCorrectionApi({this.startResult, this.confirmResult});

  Map<String, dynamic>? startResult;
  Map<String, dynamic>? confirmResult;
  final starts = <Map<String, dynamic>>[];
  final confirms = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> start({
    required String userId,
    required String currentEmail,
    required String password,
    String? newName,
    String? newEmail,
  }) async {
    starts.add({
      'userId': userId,
      'currentEmail': currentEmail,
      'password': password,
      'newName': newName,
      'newEmail': newEmail,
    });
    return startResult ??
        {
          'success': true,
          'correctionId': 'c1',
          'needsNewEmailCode': newEmail != null,
          'sentTo': 'o***@example.com',
          'newEmailSentTo': newEmail == null ? null : 'n***@example.com',
        };
  }

  @override
  Future<Map<String, dynamic>> confirm({
    required String userId,
    required String correctionId,
    required String code,
    String? newEmailCode,
  }) async {
    confirms.add({
      'correctionId': correctionId,
      'code': code,
      'newEmailCode': newEmailCode,
    });
    return confirmResult ??
        {'success': true, 'name': 'Jon Smith', 'email': 'owner@example.com'};
  }
}

Future<void> _open(
  WidgetTester tester,
  FakeCorrectionApi api, {
  void Function(String, String)? onSaved,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: AccountCorrectionScreen(
      currentName: 'Jon Smiht',
      currentEmail: 'owner@example.com',
      api: api,
      onCorrected: (name, email) async => onSaved?.call(name, email),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _fillCredentials(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('correction-current-email')), 'owner@example.com');
  await tester.enterText(
      find.byKey(const Key('correction-password')), 'Secret-1');
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'userId': '7'});
  });

  testWidgets('a name fix sends a code, then saves only after confirmation',
      (tester) async {
    final api = FakeCorrectionApi();
    String? savedName;
    await _open(tester, api, onSaved: (name, _) => savedName = name);

    await tester.enterText(
        find.byKey(const Key('correction-name')), 'Jon Smith');
    await _fillCredentials(tester);
    await tester.tap(find.byKey(const Key('correction-send-code')));
    await tester.pumpAndSettle();

    expect(api.starts.single['newName'], 'Jon Smith');
    expect(api.starts.single['newEmail'], isNull);
    expect(api.starts.single['password'], 'Secret-1');
    expect(savedName, isNull, reason: 'nothing saves before the code');
    expect(find.byKey(const Key('correction-code')), findsOneWidget);
    expect(find.byKey(const Key('correction-new-email-code')), findsNothing);

    await tester.enterText(find.byKey(const Key('correction-code')), '123456');
    await tester.tap(find.byKey(const Key('correction-confirm')));
    await tester.pumpAndSettle();

    expect(api.confirms.single['code'], '123456');
    expect(savedName, 'Jon Smith');
  });

  testWidgets('an email change asks for both codes', (tester) async {
    final api = FakeCorrectionApi(
      confirmResult: {
        'success': true,
        'name': 'Jon Smiht',
        'email': 'new@example.com',
      },
    );
    String? savedEmail;
    await _open(tester, api, onSaved: (_, email) => savedEmail = email);

    await tester.enterText(
        find.byKey(const Key('correction-new-email')), 'new@example.com');
    await _fillCredentials(tester);
    await tester.tap(find.byKey(const Key('correction-send-code')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('correction-new-email-code')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('correction-code')), '111111');
    await tester.tap(find.byKey(const Key('correction-confirm')));
    await tester.pumpAndSettle();
    expect(api.confirms, isEmpty, reason: 'both codes are required');

    await tester.enterText(
        find.byKey(const Key('correction-new-email-code')), '222222');
    await tester.tap(find.byKey(const Key('correction-confirm')));
    await tester.pumpAndSettle();
    expect(api.confirms.single['newEmailCode'], '222222');
    expect(savedEmail, 'new@example.com');
  });

  testWidgets('a wrong password shows a clear message and sends no code',
      (tester) async {
    final api = FakeCorrectionApi(
      startResult: {'success': false, 'code': 'credentials_mismatch'},
    );
    await _open(tester, api);

    await tester.enterText(
        find.byKey(const Key('correction-name')), 'Jon Smith');
    await _fillCredentials(tester);
    await tester.tap(find.byKey(const Key('correction-send-code')));
    await tester.pumpAndSettle();

    expect(
      find.text('The email or password does not match this account.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('correction-code')), findsNothing);
  });

  testWidgets('nothing changed means no request', (tester) async {
    final api = FakeCorrectionApi();
    await _open(tester, api);
    await _fillCredentials(tester);
    await tester.tap(find.byKey(const Key('correction-send-code')));
    await tester.pumpAndSettle();

    expect(api.starts, isEmpty);
    expect(find.text('Change your name or email first.'), findsOneWidget);
  });
}
