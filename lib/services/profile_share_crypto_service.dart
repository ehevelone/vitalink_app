import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'secure_store.dart';
import '../l10n/app_strings.dart';
import '../l10n/screen_strings.dart';

class ProfileShareCryptoService {
  ProfileShareCryptoService([SecureStore? store])
      : _store = store ?? SecureStore();

  final SecureStore _store;
  final AesGcm _cipher = AesGcm.with256bits();

  String _keyName(String shareId) => 'profileShareKey:$shareId';

  String generateKey() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<String> createAndStoreKey(String shareId) async {
    final encoded = generateKey();
    await _store.setString(_keyName(shareId), encoded);
    return encoded;
  }

  Future<void> storeKey(String shareId, String encodedKey) async {
    _decodeKey(encodedKey);
    await _store.setString(_keyName(shareId), encodedKey);
  }

  Future<String?> loadKey(String shareId) =>
      _store.getString(_keyName(shareId));

  Future<void> deleteKey(String shareId) => _store.remove(_keyName(shareId));

  String makeInviteToken(String inviteCode, String encodedKey) =>
      makeToken(inviteCode, encodedKey);

  String makeToken(String code, String encodedKey) => '$code.$encodedKey';

  ({String inviteCode, String encodedKey}) parseInviteToken(String token) {
    final parsed = parseToken(token);
    return (inviteCode: parsed.code, encodedKey: parsed.encodedKey);
  }

  ({String code, String encodedKey}) parseToken(String token) {
    final separator = token.indexOf('.');
    if (separator <= 0 || separator == token.length - 1) {
      throw FormatException(AppStrings.current().enterCompleteCode);
    }
    final code = token.substring(0, separator).trim().toUpperCase();
    final encodedKey = token.substring(separator + 1).trim();
    _decodeKey(encodedKey);
    return (code: code, encodedKey: encodedKey);
  }

  Future<String> encryptJson(
    Map<String, dynamic> payload,
    String encodedKey,
  ) async {
    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(_decodeKey(encodedKey)),
      nonce: nonce,
    );
    return [
      'v1',
      base64UrlEncode(nonce).replaceAll('=', ''),
      base64UrlEncode(box.cipherText).replaceAll('=', ''),
      base64UrlEncode(box.mac.bytes).replaceAll('=', ''),
    ].join('.');
  }

  Future<Map<String, dynamic>> decryptJson(
    String encrypted,
    String encodedKey,
  ) async {
    final parts = encrypted.split('.');
    if (parts.length != 4 || parts.first != 'v1') {
      throw FormatException(AppStrings.current().unsupportedSharePackage);
    }
    final clear = await _cipher.decrypt(
      SecretBox(
        _decodeBase64(parts[2]),
        nonce: _decodeBase64(parts[1]),
        mac: Mac(_decodeBase64(parts[3])),
      ),
      secretKey: SecretKey(_decodeKey(encodedKey)),
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map);
  }

  List<int> _decodeKey(String encoded) {
    final bytes = _decodeBase64(encoded);
    if (bytes.length != 32) {
      throw FormatException(AppStrings.current().invalidShareKey);
    }
    return bytes;
  }

  List<int> _decodeBase64(String value) {
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return base64Url.decode(padded);
  }
}
