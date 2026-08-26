import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class PersistentFileStore {
  static Future<String> saveImageFile(
    String sourcePath, {
    required String folder,
    String fallbackExtension = 'jpg',
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;

    final bytes = await source.readAsBytes();
    return saveBytes(
      bytes,
      folder: folder,
      extension: _extensionFromPath(sourcePath, fallbackExtension),
    );
  }

  static Future<String> saveBytes(
    List<int> bytes, {
    required String folder,
    String extension = 'jpg',
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final targetDir = Directory(
      '${root.path}${Platform.pathSeparator}vitalink_files'
      '${Platform.pathSeparator}$folder',
    );
    await targetDir.create(recursive: true);

    final safeExtension = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    final target = File('${targetDir.path}${Platform.pathSeparator}$fileName');

    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  static Future<Map<String, dynamic>> attachProfileFileBytes(
    Map<String, dynamic> payload,
  ) async {
    final copy = _deepCopyMap(payload);
    final attachments = <Map<String, dynamic>>[];
    final attachmentByPath = <String, int>{};

    Future<void> collect(List<Object> location, String? path) async {
      final trimmed = path?.trim() ?? '';
      if (trimmed.isEmpty) return;

      final file = File(trimmed);
      if (!await file.exists()) return;

      final normalizedPath = file.absolute.path;
      final existingIndex = attachmentByPath[normalizedPath];
      if (existingIndex != null) {
        (attachments[existingIndex]['locations'] as List).add(location);
        return;
      }

      final index = attachments.length;
      attachmentByPath[normalizedPath] = index;
      attachments.add({
        'locations': [location],
        'extension': _extensionFromPath(trimmed, 'jpg'),
        'base64': base64Encode(await file.readAsBytes()),
      });
    }

    await _collectInsuranceFiles(copy, collect);

    if (attachments.isNotEmpty) {
      copy['_vitalinkFileAttachments'] = attachments;
    }

    return copy;
  }

  static Future<Map<String, dynamic>> restoreProfileFileBytes(
    Map<String, dynamic> payload,
  ) async {
    final copy = _deepCopyMap(payload);
    final attachments = copy.remove('_vitalinkFileAttachments');

    if (attachments is! List) return copy;

    for (final rawAttachment in attachments) {
      if (rawAttachment is! Map) continue;

      final base64Data = rawAttachment['base64']?.toString() ?? '';
      final locations = rawAttachment['locations'];
      if (base64Data.isEmpty || locations is! List) continue;

      try {
        final bytes = base64Decode(base64Data);
        final savedPath = await saveBytes(
          Uint8List.fromList(bytes),
          folder: 'shared_profile_files',
          extension: rawAttachment['extension']?.toString() ?? 'jpg',
        );

        for (final rawLocation in locations) {
          if (rawLocation is List) {
            _setLocation(copy, rawLocation, savedPath);
          }
        }
      } catch (_) {
        continue;
      }
    }

    return copy;
  }

  static Future<void> _collectInsuranceFiles(
    Map<String, dynamic> payload,
    Future<void> Function(List<Object> location, String? path) collect,
  ) async {
    final orphanCards = payload['orphanCards'];
    if (orphanCards is List) {
      for (var i = 0; i < orphanCards.length; i += 1) {
        final card = orphanCards[i];
        if (card is Map) {
          await _collectCardFiles(['orphanCards', i], card, collect);
        }
      }
    }

    final insurances = payload['insurances'];
    if (insurances is List) {
      for (var i = 0; i < insurances.length; i += 1) {
        final insurance = insurances[i];
        if (insurance is! Map) continue;

        final decPagePaths = insurance['decPagePaths'];
        if (decPagePaths is List) {
          for (var j = 0; j < decPagePaths.length; j += 1) {
            await collect(
              ['insurances', i, 'decPagePaths', j],
              decPagePaths[j]?.toString(),
            );
          }
        }

        final cards = insurance['cards'];
        if (cards is List) {
          for (var j = 0; j < cards.length; j += 1) {
            final card = cards[j];
            if (card is Map) {
              await _collectCardFiles(
                ['insurances', i, 'cards', j],
                card,
                collect,
              );
            }
          }
        }
      }
    }
  }

  static Future<void> _collectCardFiles(
    List<Object> baseLocation,
    Map card,
    Future<void> Function(List<Object> location, String? path) collect,
  ) async {
    await collect([...baseLocation, 'frontImagePath'], card['frontImagePath']?.toString());
    await collect([...baseLocation, 'backImagePath'], card['backImagePath']?.toString());
    await collect([...baseLocation, 'imagePath'], card['imagePath']?.toString());
  }

  static void _setLocation(
    Map<String, dynamic> root,
    List<dynamic> location,
    String value,
  ) {
    dynamic current = root;

    for (var i = 0; i < location.length - 1; i += 1) {
      final segment = location[i];
      if (segment is int && current is List && segment < current.length) {
        current = current[segment];
      } else if (segment is String && current is Map) {
        current = current[segment];
      } else {
        return;
      }
    }

    final last = location.last;
    if (last is int && current is List && last < current.length) {
      current[last] = value;
    } else if (last is String && current is Map) {
      current[last] = value;
    }
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);
  }

  static String _extensionFromPath(String path, String fallback) {
    final fileName = path.split(RegExp(r'[\\/]')).last;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return fallback;

    final extension = fileName.substring(dot + 1).toLowerCase();
    if (extension.length > 5) return fallback;
    return extension;
  }
}
