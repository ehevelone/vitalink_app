import 'dart:io';

import 'package:image/image.dart' as image_lib;

const int _maxLabelImageSide = 2048;
const int _maxLabelImageBytes = 700 * 1024;
const int _labelJpegQuality = 88;

/// Shrinks a label photo in place when it is larger than the scanner needs,
/// so four pages stay well under the label scanner's upload limit.
/// Returns the same path; on any failure the original file is left as is.
Future<String> compressLabelPhoto(String path) async {
  try {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final image = image_lib.decodeImage(bytes);
    if (image == null) return path;

    final longestSide = image.width > image.height ? image.width : image.height;
    if (longestSide <= _maxLabelImageSide &&
        bytes.length <= _maxLabelImageBytes) {
      return path;
    }

    final resized = longestSide <= _maxLabelImageSide
        ? image
        : image_lib.copyResize(
            image,
            width: image.width >= image.height ? _maxLabelImageSide : null,
            height: image.height > image.width ? _maxLabelImageSide : null,
            interpolation: image_lib.Interpolation.average,
          );
    await file.writeAsBytes(
      image_lib.encodeJpg(resized, quality: _labelJpegQuality),
      flush: true,
    );
  } catch (_) {}
  return path;
}
