import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/services/profile_share_crypto_service.dart';

void main() {
  group('ProfileShareCryptoService', () {
    final crypto = ProfileShareCryptoService();

    test('keeps the case-sensitive key intact in a complete token', () {
      final key = crypto.generateKey();
      final token = crypto.makeToken('vt-ab12', key);
      final parsed = crypto.parseToken(token);

      expect(parsed.code, 'VT-AB12');
      expect(parsed.encodedKey, key);
    });

    test('encrypts and decrypts a profile package locally', () async {
      final key = crypto.generateKey();
      final encrypted = await crypto.encryptJson({
        'profileName': 'Test User',
        'medications': ['Example medication'],
      }, key);

      expect(encrypted, isNot(contains('Test User')));
      final decrypted = await crypto.decryptJson(encrypted, key);
      expect(decrypted['profileName'], 'Test User');
      expect(decrypted['medications'], ['Example medication']);
    });

    test('rejects a partial code without its encryption key', () {
      expect(
        () => crypto.parseToken('VT-AB12'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
