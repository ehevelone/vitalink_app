import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'data_repository.dart';
import 'device_id.dart';
import 'profile_share_crypto_service.dart';
import 'secure_store.dart';

class DeviceTransferService {
  static const int _chunkSize = 1500000;
  DeviceTransferService({
    DataRepository? repository,
    SecureStore? store,
  })  : _repository = repository ?? DataRepository(),
        _store = store ?? SecureStore();

  final DataRepository _repository;
  final SecureStore _store;
  final ProfileShareCryptoService _crypto = ProfileShareCryptoService();

  Future<Map<String, dynamic>> createTransfer() async {
    final userId = await _requireUserId();
    final deviceId = await DeviceId.getOrCreate();
    final payload = await _repository.exportDeviceTransferPayload();
    final files = await _collectLocalFiles(payload);
    final shareKeys = await _collectShareKeys(userId, payload);
    final key = _crypto.generateKey();
    final encryptedPayload = await _crypto.encryptJson({
      ...payload,
      'files': files,
      'shareKeys': shareKeys,
    }, key);
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
    );

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Unable to create transfer.');
    }

    final serverCode = result['transferCode']?.toString() ?? '';
    final transferId = result['transferId']?.toString() ?? '';
    if (serverCode.isEmpty || transferId.isEmpty) {
      throw Exception('Unable to create transfer code.');
    }
    for (var i = 0; i < chunks.length; i += 1) {
      final upload = await ApiService.uploadDeviceTransferChunk(
        userId: userId,
        deviceId: deviceId,
        transferId: transferId,
        chunkIndex: i,
        chunkData: chunks[i],
      );
      if (upload['success'] != true) {
        throw Exception(upload['error'] ?? 'Unable to upload transfer data.');
      }
    }
    return {
      ...result,
      'transferCode': _crypto.makeToken(serverCode, key),
    };
  }

  Future<Map<String, dynamic>> checkPendingTransfer() async {
    final userId = await _requireUserId();
    final deviceId = await DeviceId.getOrCreate();
    final result = await ApiService.checkDeviceTransfer(
      userId: userId,
      deviceId: deviceId,
    );

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Unable to check transfer status.');
    }

    return result;
  }

  Future<void> redeemTransfer(String code) async {
    final userId = await _requireUserId();
    final deviceId = await DeviceId.getOrCreate();
    final parsed = _crypto.parseToken(code);
    final result = await ApiService.redeemDeviceTransfer(
      userId: userId,
      deviceId: deviceId,
      transferCode: parsed.code,
    );

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Unable to load transfer.');
    }

    final transferId = result['transferId']?.toString() ?? '';
    final chunkCount = result['chunkCount'] is int
        ? result['chunkCount'] as int
        : int.tryParse(result['chunkCount']?.toString() ?? '') ?? 0;
    if (transferId.isEmpty || chunkCount < 1) {
      throw Exception('This transfer package is not available.');
    }
    final encryptedBuffer = StringBuffer();
    for (var i = 0; i < chunkCount; i += 1) {
      final chunk = await ApiService.getDeviceTransferChunk(
        userId: userId,
        deviceId: deviceId,
        transferId: transferId,
        chunkIndex: i,
      );
      if (chunk['success'] != true || chunk['chunkData'] == null) {
        throw Exception(chunk['error'] ?? 'Unable to download transfer data.');
      }
      encryptedBuffer.write(chunk['chunkData']);
    }
    final payload = await _crypto.decryptJson(
      encryptedBuffer.toString(),
      parsed.encodedKey,
    );
    final files = Map<String, dynamic>.from(payload['files'] as Map? ?? {});
    final shareKeys = Map<String, dynamic>.from(
      payload['shareKeys'] as Map? ?? {},
    );
    final restoredPaths = await _restoreLocalFiles(files);
    payload.remove('files');
    payload.remove('shareKeys');

    if (restoredPaths.isNotEmpty) {
      _rewriteTransferredPaths(payload, restoredPaths);
    }

    await _repository.importDeviceTransferPayload(payload);
    for (final entry in shareKeys.entries) {
      final encodedKey = entry.value?.toString() ?? '';
      if (encodedKey.isNotEmpty) {
        await _crypto.storeKey(entry.key, encodedKey);
      }
    }
    if (transferId.isNotEmpty) {
      final completed = await ApiService.completeDeviceTransfer(
        userId: userId,
        deviceId: deviceId,
        transferId: transferId,
      );
      if (completed['success'] != true) {
        throw Exception(
          completed['error'] ?? 'Profile loaded, but transfer cleanup failed.',
        );
      }
    }
  }

  Future<String> _requireUserId() async {
    final userId = await _store.getString('userId');
    if (userId == null || userId.isEmpty) {
      throw Exception('Please log in before moving VitaLink to a new device.');
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

  Future<Map<String, String>> _collectLocalFiles(
    Map<String, dynamic> payload,
  ) async {
    final paths = <String>{};
    _collectPaths(payload, paths);

    final files = <String, String>{};

    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;

      final bytes = await file.readAsBytes();
      files[path] = base64Encode(bytes);
    }

    return files;
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

  Future<Map<String, String>> _restoreLocalFiles(
    Map<String, dynamic> files,
  ) async {
    if (files.isEmpty) return {};

    final dir = await getApplicationDocumentsDirectory();
    final transferDir = Directory('${dir.path}/vitalink_transfers');
    await transferDir.create(recursive: true);

    final restored = <String, String>{};

    for (final entry in files.entries) {
      final originalPath = entry.key;
      final encoded = entry.value?.toString() ?? '';
      if (encoded.isEmpty) continue;

      final bytes = base64Decode(encoded);
      final fileName = _safeFileName(originalPath);
      final newPath =
          '${transferDir.path}/${DateTime.now().microsecondsSinceEpoch}_$fileName';

      await File(newPath).writeAsBytes(bytes, flush: true);
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
}
