import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'data_repository.dart';
import 'secure_store.dart';

class DeviceTransferService {
  DeviceTransferService({
    DataRepository? repository,
    SecureStore? store,
  })  : _repository = repository ?? DataRepository(),
        _store = store ?? SecureStore();

  final DataRepository _repository;
  final SecureStore _store;

  Future<Map<String, dynamic>> createTransfer() async {
    final userId = await _requireUserId();
    final payload = await _repository.exportDeviceTransferPayload();
    final files = await _collectLocalFiles(payload);

    final result = await ApiService.createDeviceTransfer(
      userId: userId,
      payload: {
        ...payload,
        'files': files,
      },
    );

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Unable to create transfer.');
    }

    return result;
  }

  Future<Map<String, dynamic>> checkPendingTransfer() async {
    final userId = await _requireUserId();
    final result = await ApiService.checkDeviceTransfer(userId: userId);

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Unable to check transfer status.');
    }

    return result;
  }

  Future<void> redeemTransfer(String code) async {
    final userId = await _requireUserId();
    final result = await ApiService.redeemDeviceTransfer(
      userId: userId,
      transferCode: code,
    );

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Unable to load transfer.');
    }

    final payload = Map<String, dynamic>.from(result['payload'] as Map? ?? {});
    final files = Map<String, dynamic>.from(payload['files'] as Map? ?? {});
    final restoredPaths = await _restoreLocalFiles(files);
    payload.remove('files');

    if (restoredPaths.isNotEmpty) {
      _rewriteTransferredPaths(payload, restoredPaths);
    }

    await _repository.importDeviceTransferPayload(payload);
  }

  Future<String> _requireUserId() async {
    final userId = await _store.getString('userId');
    if (userId == null || userId.isEmpty) {
      throw Exception('Please log in before moving VitaLink to a new device.');
    }
    return userId;
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
