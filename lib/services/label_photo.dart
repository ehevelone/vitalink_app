import 'dart:io';

import 'package:image/image.dart' as image_lib;

/// Each label photo must end up at or under this size so four photos stay well
/// under the label scanner's ~6 MB upload limit (photos grow ~33% as Base64).
const int maxLabelPhotoBytes = 700 * 1024;

/// Total photo bytes allowed in one scan request (before Base64).
const int maxLabelScanBytes = 4 * 1024 * 1024;

const int _maxLabelImageSide = 2048;

// Tried in order until the photo fits: same size at lower quality first, then
// smaller sizes, which keep small print readable longer than very low quality.
const _attempts = [
  (side: 2048, quality: 88),
  (side: 2048, quality: 80),
  (side: 1800, quality: 78),
  (side: 1600, quality: 75),
  (side: 1400, quality: 72),
  (side: 1200, quality: 70),
  // Last resorts for extremely busy photos; real labels rarely get here.
  (side: 1000, quality: 65),
  (side: 800, quality: 60),
];

/// Shrinks a label photo in place until it is at or under
/// [maxLabelPhotoBytes]. Returns the same path. If the photo cannot be read,
/// it is left as is; callers check the final size with [labelPhotoFits].
Future<String> compressLabelPhoto(String path) async {
  try {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final image = image_lib.decodeImage(bytes);
    if (image == null) return path;

    final longestSide = image.width > image.height ? image.width : image.height;
    if (longestSide <= _maxLabelImageSide && bytes.length <= maxLabelPhotoBytes) {
      return path;
    }

    List<int>? smallest;
    for (final attempt in _attempts) {
      final resized = longestSide <= attempt.side
          ? image
          : image_lib.copyResize(
              image,
              width: image.width >= image.height ? attempt.side : null,
              height: image.height > image.width ? attempt.side : null,
              interpolation: image_lib.Interpolation.average,
            );
      final encoded = image_lib.encodeJpg(resized, quality: attempt.quality);
      if (smallest == null || encoded.length < smallest.length) {
        smallest = encoded;
      }
      if (encoded.length <= maxLabelPhotoBytes) break;
    }
    if (smallest != null && smallest.length < bytes.length) {
      await file.writeAsBytes(smallest, flush: true);
    }
  } catch (_) {}
  return path;
}

/// True when all photos together fit in one scan request.
Future<bool> labelPhotosFit(List<String> paths) async {
  var total = 0;
  for (final path in paths) {
    try {
      total += await File(path).length();
    } catch (_) {
      return false;
    }
  }
  return total <= maxLabelScanBytes;
}
