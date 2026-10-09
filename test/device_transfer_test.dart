import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/services/data_repository.dart';
import 'package:vitalink/services/profile_share_crypto_service.dart';
import 'package:vitalink/services/secure_store.dart';
import 'package:vitalink/services/transfer_code.dart';

// Real profile ids are UUIDs; short ids would be migrated on load.
String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransferCode', () {
    test('short codes format to 18 characters and parse back', () {
      final secret = TransferCode.generateSecret(Random(1));
      final shown = TransferCode.format('K7QM4TZP', secret);
      expect(shown, matches(RegExp(r'^\w{4}-\w{4}-\w{5}-\w{5}$')));

      final parsed = TransferCode.parse(shown);
      expect(parsed.serverCode, 'K7QM4TZP');
      expect(parsed.secret, secret);
      expect(parsed.isLegacy, isFalse);
    });

    test('typing differences still match: case, spaces, look-alike letters',
        () {
      final parsed = TransferCode.parse('k7qm 4tzp-9xwd2-rabcO ');
      expect(parsed.serverCode, 'K7QM4TZP');
      expect(parsed.secret, '9XWD2RABC0', reason: 'O is read as zero');
      expect(TransferCode.parse('K7QM4TZP9XWD2RABCL').secret, '9XWD2RABC1');
    });

    test('incomplete codes are rejected before anything is sent', () {
      expect(() => TransferCode.parse('K7QM-4TZP-9XWD'),
          throwsA(isA<FormatException>()));
      expect(() => TransferCode.parse(''), throwsA(isA<FormatException>()));
    });

    test('older code-plus-key tokens are still accepted', () {
      final key = ProfileShareCryptoService().generateKey();
      final parsed = TransferCode.parse('VT-ABC123.$key');
      expect(parsed.isLegacy, isTrue);
      expect(parsed.serverCode, 'VT-ABC123');
      expect(parsed.legacyKey, key);
    });

    test('both phones derive the same key and can decrypt the package',
        () async {
      final keyOnOldPhone =
          await TransferCode.deriveKey(secret: '9XWD2RABC0', userId: '42');
      final keyOnNewPhone = await TransferCode.parse('K7QM4TZP9XWD2RABC0')
          .encryptionKey('42');
      expect(keyOnNewPhone, keyOnOldPhone);
      expect(base64Url.decode(base64Url.normalize(keyOnOldPhone)).length, 32);

      final crypto = ProfileShareCryptoService();
      final encrypted =
          await crypto.encryptJson({'profiles': ['Pat']}, keyOnOldPhone);
      expect(await crypto.decryptJson(encrypted, keyOnNewPhone),
          {'profiles': ['Pat']});

      final wrongAccount =
          await TransferCode.deriveKey(secret: '9XWD2RABC0', userId: '43');
      expect(wrongAccount, isNot(keyOnOldPhone));
    });
  });

  group('transfer import', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureStore();
      await store.setString('userId', '42');
      await store.setString('userSessionToken', 'session');
    });

    Map<String, dynamic> payload(List<Profile> profiles, int active) => {
          'version': 1,
          'activeProfileIndex': active,
          'profiles': profiles.map((p) => p.toJson()).toList(),
        };

    test('merges into existing profiles instead of overwriting them', () async {
      final repo = DataRepository();
      await repo.addProfile(Profile(id: _id(1), fullName: 'Entered Here'));
      await repo.addProfile(Profile(id: _id(2), fullName: 'Old Copy'));

      await repo.importDeviceTransferPayload(payload([
        Profile(id: _id(2), fullName: 'From Old Phone'),
        Profile(id: _id(3), fullName: 'Spouse'),
      ], 1));

      final profiles = await repo.loadAllProfiles();
      expect(profiles.map((p) => p.fullName),
          ['Entered Here', 'From Old Phone', 'Spouse']);
      expect((await repo.loadProfile()).fullName, 'Spouse',
          reason: 'the old phone\'s active profile stays active');
    });

    test('drops the empty placeholder profile created on first launch',
        () async {
      final repo = DataRepository();
      await repo.loadProfile(); // creates the blank placeholder

      await repo.importDeviceTransferPayload(
        payload([Profile(id: _id(4), fullName: 'Pat Client')], 0),
      );

      final profiles = await repo.loadAllProfiles();
      expect(profiles.map((p) => p.fullName), ['Pat Client']);
    });
  });
}
