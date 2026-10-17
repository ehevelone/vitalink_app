import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/screens/profile_user_screen.dart';
import 'package:vitalink/services/data_repository.dart';
import 'package:vitalink/services/secure_store.dart';

Future<void> _signInUser(String id) async {
  final store = SecureStore();
  await store.clearAuth();
  await store.setString('userId', id);
  await store.setString('userSessionToken', 'session-$id');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('the registered profile is the account holder; family profiles are not',
      () async {
    await _signInUser('101');
    final repo = DataRepository();
    final holder = await repo.loadProfile();
    holder.fullName = 'John Holder';
    await repo.saveProfile(holder);
    await repo.markAccountProfile(holder.id);

    final family = Profile(fullName: 'Jane Family');
    await repo.addProfile(family);

    expect(await repo.isAccountProfile(holder), isTrue);
    expect(await repo.isAccountProfile(family), isFalse);
  });

  test('older accounts treat the first profile as the account holder',
      () async {
    await _signInUser('202');
    final repo = DataRepository();
    final first = await repo.loadProfile();
    final second = Profile(fullName: 'Second Person');
    await repo.addProfile(second);

    expect(await repo.isAccountProfile(first), isTrue);
    expect(await repo.isAccountProfile(second), isFalse);
  });
  test("the account holder profile cannot be deleted; family profiles can",
      () async {
    await _signInUser("303");
    final repo = DataRepository();
    final holder = await repo.loadProfile();
    await repo.markAccountProfile(holder.id);
    await repo.addProfile(Profile(fullName: "Jane Family"));
    await repo.setActiveProfileIndex(1);

    await repo.deleteProfileAt(0);
    var profiles = await repo.loadAllProfiles();
    expect(profiles.map((p) => p.id), contains(holder.id));
    expect(profiles.length, 2);

    await repo.setActiveProfileIndex(0);
    await repo.deleteProfileAt(1);
    profiles = await repo.loadAllProfiles();
    expect(profiles.length, 1);
    expect(profiles.single.id, holder.id);
  });

  testWidgets('account name and email are locked; family name stays editable',
      (tester) async {
    await _signInUser('404');
    final store = SecureStore();
    await store.setString('userEmail', 'john@example.com');
    final repo = DataRepository();
    final holder = await repo.loadProfile();
    holder.fullName = 'John Holder';
    await repo.saveProfile(holder);
    await repo.markAccountProfile(holder.id);
    await repo.addProfile(Profile(fullName: 'Jane Family'));

    Future<void> openProfile() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        const MaterialApp(home: ProfileUserScreen()),
      );
      await tester.pumpAndSettle();
    }

    EditableText fieldWithText(String text) => tester
        .widgetList<EditableText>(find.byType(EditableText))
        .singleWhere((field) => field.controller.text == text);

    await repo.setActiveProfileIndex(0);
    await openProfile();
    expect(fieldWithText('John Holder').readOnly, isTrue);
    expect(fieldWithText('john@example.com').readOnly, isTrue);

    await repo.setActiveProfileIndex(1);
    await openProfile();
    expect(fieldWithText('Jane Family').readOnly, isFalse);
    expect(find.text('john@example.com'), findsNothing);
  });
}
