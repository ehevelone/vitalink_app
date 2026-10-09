import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import '../l10n/app_strings.dart';
import '../l10n/screen_strings.dart';

/// Short, typeable device-transfer codes.
///
/// A code is 18 characters: an 8-character server lookup code followed by a
/// 10-character secret, shown as `XXXX-XXXX-XXXXX-XXXXX`. Only the lookup
/// part is ever sent to the server; the secret is stretched into the AES key
/// on each phone, so the server still cannot read the transferred profiles.
///
/// Older app versions produced `<server code>.<base64 key>` tokens; [parse]
/// still accepts those.
class TransferCode {
  TransferCode._(this.serverCode, this.secret, this.legacyKey);

  /// Crockford base32: no I, L, O or U, so codes are easy to read and type.
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const serverCodeLength = 8;
  static const secretLength = 10;
  static const _kdfIterations = 100000;

  final String serverCode;
  final String? secret;
  final String? legacyKey;

  bool get isLegacy => legacyKey != null;

  static String generateSecret([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      secretLength,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  /// Display form: XXXX-XXXX-XXXXX-XXXXX.
  static String format(String serverCode, String secret) {
    final all = '$serverCode$secret';
    return [
      all.substring(0, 4),
      all.substring(4, 8),
      all.substring(8, 13),
      all.substring(13),
    ].join('-');
  }

  /// Uppercases, drops spaces/dashes and maps look-alikes (O→0, I/L→1) so
  /// minor typing differences still match.
  static String normalize(String input) => input
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp(r'[IL]'), '1');

  static TransferCode parse(String input) {
    final trimmed = input.trim();
    final dot = trimmed.indexOf('.');
    if (dot > 0) {
      final key = trimmed.substring(dot + 1).trim();
      if (key.isEmpty) {
        throw FormatException(AppStrings.current().enterCompleteCode);
      }
      return TransferCode._(
        trimmed.substring(0, dot).trim().toUpperCase(),
        null,
        key,
      );
    }

    final code = normalize(trimmed);
    if (code.length != serverCodeLength + secretLength ||
        code.split('').any((c) => !alphabet.contains(c))) {
      throw FormatException(AppStrings.current().transferCodeWrongLength);
    }
    return TransferCode._(
      code.substring(0, serverCodeLength),
      code.substring(serverCodeLength),
      null,
    );
  }

  /// Stretches the short secret into a 256-bit key (base64url, no padding),
  /// the format ProfileShareCryptoService expects. The account id is the salt
  /// because both phones know it once signed in.
  static Future<String> deriveKey({
    required String secret,
    required String userId,
  }) async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _kdfIterations,
      bits: 256,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: secret,
      nonce: utf8.encode('vitalink-transfer-v2:$userId'),
    );
    return base64UrlEncode(await key.extractBytes()).replaceAll('=', '');
  }

  /// The key for this code: the embedded key for legacy tokens, otherwise
  /// derived from the secret.
  Future<String> encryptionKey(String userId) async =>
      legacyKey ?? await deriveKey(secret: secret!, userId: userId);
}
