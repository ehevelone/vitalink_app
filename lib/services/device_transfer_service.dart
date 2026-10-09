import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'data_repository.dart';
import 'device_id.dart';
import 'profile_share_crypto_service.dart';
import 'secure_store.dart';
import 'transfer_code.dart';
import '../l10n/app_strings.dart';
import '../l10n/screen_strings.dart';

class DeviceTransferService {
  static const int _chunkSize = 1500000;
  static const List<Duration> _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  DeviceTransferService({
    DataRepository? repository,
    SecureStore? store,
  })  : _repository = repository ?? DataRepository(),
        _store = store ?? SecureStore();

  final DataRepository _repository;
  final SecureStore _store;
  final ProfileShareCryptoService _crypto = ProfileShareCryptoService();

  /// Packages this phone's profiles and returns the transfer code to show the
  /// user (`transferCode`), formatted for typing on the new phone.
  Future<Map<String, dynamic>> createTransfer() async {
    final userId = await _requireUserId();
    final deviceId = await DeviceId.getOrCreate();
    final payload = await _repository.exportDeviceTransferPayload();
    final shareKeys = await _collectShareKeys(userId, payload);
    final filePaths = <String>{};
    _collectPaths(payload, filePaths);
    final secret = TransferCode.generateSecret();

    // Reading photos, key stretching and encryption are CPU-heavy; keep them
    // off the UI thread so slower phones don't freeze or show "not responding".
    final package = await Isolate.run(
      () => _encryptPackage(
        payload: payload,
        filePaths: filePaths.toList(),
        shareKeys: shareKeys,
        secret: secret,
        userId: userId,
      ),
    );
    final encryptedPayload = package['encrypted']!;
    final chunks = <String>[];
    for (var offset = 0;
        offset < encryptedPayload.length;
        offset += _chunkSize) {
      final end = offset + _chunkSize < encryptedPayload.length
          ? offset + _chunkSize
          : encryptedPayload.length;
      chunks.add(encryptedPayload.substring(offset, end));
    }

    final result = await ApiService.createDeviceTransfer(
      userId: userId,
      deviceId: deviceId,
      chunkCount: chunks.length,
      codeFormat: 'short',
    );

    if (result['success'] != true) {
      throw Exception(
          result['error'] ?? AppStrings.current().unableToCreateTransfer);
    }

    final serverCode = result['transferCode']?.toString() ?? '';
    final transferId = result['transferId']?.toString() ?? '';
    if (serverCode.isEmpty || transferId.isEmpty) {
      throw Exception(AppStrings.current().unableToCreateTransferCode);
    }
    for (var i = 0; i < chunks.length; i += 1) {
      final upload = await _withRetry(
        () => ApiService.uploadDeviceTransferChunk(
          userId: userId,
          deviceId: deviceId,
          transferId: transferId,
          chunkIndex: i,
          chunkData: chunks[i],
        ),
      );
      if (upload['success'] != true) {
        throw Exception(
            upload['error'] ?? AppStrings.current().unableToUploadTransfer);
      }
    }

    // A server that predates short codes returns a long "VT-" code; fall back
    // to the older code-plus-key form the redeeming phone also understands.
    final displayCode = serverCode.length == TransferCode.serverCodeLength
        ? TransferCode.format(serverCode, secret)
        : _crypto.makeToken(serverCode, package['key']!);
    return {...result, 'transferCode': displayCode};
  }

  Future<Map<String, dynamic>> checkPendingTransfer() async {
    final userId = await _requireUserId();
    final deviceId = await DeviceId.getOrCreate();
    final result = await ApiService.checkDeviceTransfer(
      userId: userId,
      deviceId: deviceId,
    );

    if (result['success'] != true) {
      throw Exception(
          result['error'] ?? AppStrings.current().unableToCheckTransfer);
    }

    return result;
  }

  /// Downloads, decrypts and merges a transfer onto this phone. Safe to call
  /// again with the same code if a previous attempt failed part-way.
  Future<void> redeemTransfer(String code) async {
    final userId = await _requireUserId();
    final deviceId = await DeviceId.getOrCreate();
    final parsed = TransferCode.parse(code);
    final result = await _withRetry(
      () => ApiService.redeemDeviceTransfer(
        userId: userId,
        deviceId: deviceId,
        transferCode: parsed.serverCode,
      ),
    );

    if (result['success'] != true) {
      throw Exception(
          result['error'] ?? AppStrings.current().unableToLoadTransfer);
    }

    final transferId = result['transferId']?.toString() ?? '';
    final chunkCount = result['chunkCount'] is int
        ? result['chunkCount'] as int
        : int.tryParse(result['chunkCount']?.toString() ?? '') ?? 0;
    if (transferId.isEmpty || chunkCount < 1) {
      throw Exception(AppStrings.current().transferPackageNotAvailable);
    }
    final encryptedBuffer = StringBuffer();
    for (var i = 0; i < chunkCount; i += 1) {
      final chunk = await _withRetry(
        () => ApiService.getDeviceTransferChunk(
          userId: userId,
          deviceId: deviceId,
          transferId: transferId,
          chunkIndex: i,
        ),
      );
      if (chunk['success'] != true || chunk['chunkData'] == null) {
        throw Exception(
            chunk['error'] ?? AppStrings.current().unableToDownloadTransfer);
      }
      encryptedBuffer.write(chunk['chunkData']);
    }

    final documentsPath = (await getApplicationDocumentsDirectory()).path;
    final encrypted = encryptedBuffer.toString();
    final secret = parsed.secret;
    final legacyKey = parsed.legacyKey;
    final decoded = await Isolate.run(
      () => _decryptPackage(
        encrypted: encrypted,
        secret: secret,
        legacyKey: legacyKey,
        userId: userId,
        documentsPath: documentsPath,
      ),
    );
    final payload = Map<String, dynamic>.from(decoded['payload'] as Map);
    final shareKeys = Map<String, dynamic>.from(
      decoded['shareKeys'] as Map? ?? const {},
    );

    await _repository.importDeviceTransferPayload(payload);
    for (final entry in shareKeys.entries) {
      final encodedKey = entry.value?.toString() ?? '';
      if (encodedKey.isNotEmpty) {
        await _crypto.storeKey(entry.key, encodedKey);
      }
    }
    final completed = await _withRetry(
      () => ApiService.completeDeviceTransfer(
        userId: userId,
        deviceId: deviceId,
        transferId: transferId,
      ),
    );
    if (completed['success'] != true) {
      // The profiles are already on this phone; the server package simply
      // expires on its own after 6 hours.
      throw TransferCleanupException(
        completed['error']?.toString() ??
            AppStrings.current().transferCleanupFailed,
      );
    }
  }

  /// Retries network failures and server errors (timeouts, 5xx); a 4xx answer
  /// such as "code not found" is returned immediately.
  static Future<Map<String, dynamic>> _withRetry(
    Future<Map<String, dynamic>> Function() call,
  ) async {
    var result = await call();
    for (final delay in _retryDelays) {
      if (result['success'] == true) return result;
      final status = result['httpStatus'];
      final retryable =
          status == null || (status is int && (status >= 500 || status == 429));
      if (!retryable) return result;
      await Future<void>.delayed(delay);
      result = await call();
    }
    return result;
  }

  Future<String> _requireUserId() async {
    final userId = await _store.getString('userId');
    if (userId == null || userId.isEmpty) {
      throw Exception(AppStrings.current().logInBeforeMoving);
    }
    return userId;
  }

  Future<Map<String, String>> _collectShareKeys(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    final keys = <String, String>{};
    final profiles = payload['profiles'] as List? ?? const [];

    for (final raw in profiles.whereType<Map>()) {
      final profile = Map<String, dynamic>.from(raw);
      final recipientShareId =
          profile['sharedRelationshipId']?.toString() ?? '';
      if (recipientShareId.isNotEmpty) {
        final key = await _crypto.loadKey(recipientShareId);
        if (key != null && key.isNotEmpty) keys[recipientShareId] = key;
      }

      final profileId = profile['id']?.toString() ?? '';
      if (profileId.isEmpty) continue;
      try {
        final result = await ApiService.getProfileShareLinks(
          userId: userId,
          profileId: profileId,
        );
        final shares = result['shares'] as List? ?? const [];
        for (final share in shares.whereType<Map>()) {
          final shareId = share['id']?.toString() ?? '';
          if (shareId.isEmpty) continue;
          final key = await _crypto.loadKey(shareId);
          if (key != null && key.isNotEmpty) keys[shareId] = key;
        }
      } catch (_) {
        // Profile data can still transfer if a sharing key is unavailable.
      }
    }
    return keys;
  }
}

/// Thrown when the profiles were imported but the server could not be told;
/// callers should treat the transfer as successful.
class TransferCleanupException implements Exception {
  TransferCleanupException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Background-isolate work. These are top-level so Isolate.run can call them
// without capturing services that hold platform channels.
// ---------------------------------------------------------------------------

Future<Map<String, String>> _encryptPackage({
  required Map<String, dynamic> payload,
  required List<String> filePaths,
  required Map<String, String> shareKeys,
  required String secret,
  required String userId,
}) async {
  final files = <String, String>{};
  for (final path in filePaths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    files[path] = base64Encode(file.readAsBytesSync());
  }
  final key = await TransferCode.deriveKey(secret: secret, userId: userId);
  final encrypted = await ProfileShareCryptoService().encryptJson({
    ...payload,
    'files': files,
    'shareKeys': shareKeys,
  }, key);
  return {'encrypted': encrypted, 'key': key};
}

Future<Map<String, dynamic>> _decryptPackage({
  required String encrypted,
  required String? secret,
  required String? legacyKey,
  required String userId,
  required String documentsPath,
}) async {
  final key = legacyKey ??
      await TransferCode.deriveKey(secret: secret!, userId: userId);
  final payload = await ProfileShareCryptoService().decryptJson(
    encrypted,
    key,
  );
  final files = Map<String, dynamic>.from(payload['files'] as Map? ?? {});
  final shareKeys = Map<String, dynamic>.from(
    payload['shareKeys'] as Map? ?? {},
  );
  payload.remove('files');
  payload.remove('shareKeys');

  final restoredPaths = _restoreLocalFiles(files, documentsPath);
  if (restoredPaths.isNotEmpty) {
    _rewriteTransferredPaths(payload, restoredPaths);
  }
  return {'payload': payload, 'shareKeys': shareKeys};
}

void _collectPaths(dynamic value, Set<String> paths) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final child = entry.value;

      if (_looksLikeLocalPathKey(key)) {
        if (child is String && child.isNotEmpty) {
          paths.add(child);
          continue;
        }

        if (child is List) {
          for (final item in child) {
            if (item is String && item.isNotEmpty) {
              paths.add(item);
            }
          }
          continue;
        }
      }

      _collectPaths(child, paths);
    }
  } else if (value is List) {
    for (final item in value) {
      _collectPaths(item, paths);
    }
  }
}

bool _looksLikeLocalPathKey(String key) {
  return key == 'imagePath' ||
      key == 'frontImagePath' ||
      key == 'backImagePath' ||
      key == 'decPagePaths';
}

Map<String, String> _restoreLocalFiles(
  Map<String, dynamic> files,
  String documentsPath,
) {
  if (files.isEmpty) return {};

  final transferDir = Directory('$documentsPath/vitalink_transfers');
  transferDir.createSync(recursive: true);

  final restored = <String, String>{};

  for (final entry in files.entries) {
    final originalPath = entry.key;
    final encoded = entry.value?.toString() ?? '';
    if (encoded.isEmpty) continue;

    final bytes = base64Decode(encoded);
    final fileName = _safeFileName(originalPath);
    final newPath =
        '${transferDir.path}/${DateTime.now().microsecondsSinceEpoch}_$fileName';

    File(newPath).writeAsBytesSync(bytes, flush: true);
    restored[originalPath] = newPath;
  }

  return restored;
}

String _safeFileName(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  final name = parts.isNotEmpty ? parts.last : 'vitalink_file';
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return cleaned.isEmpty ? 'vitalink_file' : cleaned;
}

void _rewriteTransferredPaths(
  Map<String, dynamic> payload,
  Map<String, String> restoredPaths,
) {
  void rewrite(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries.toList()) {
        final child = entry.value;
        if (child is String && restoredPaths.containsKey(child)) {
          value[entry.key] = restoredPaths[child];
        } else {
          rewrite(child);
        }
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final child = value[i];
        if (child is String && restoredPaths.containsKey(child)) {
          value[i] = restoredPaths[child];
        } else {
          rewrite(child);
        }
      }
    }
  }

  rewrite(payload);
}
