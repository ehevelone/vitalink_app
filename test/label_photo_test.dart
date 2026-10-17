import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:vitalink/services/label_photo.dart';

void main() {
  test('a large noisy photo is shrunk to fit the per-photo limit', () async {
    // Random noise compresses badly, like a busy, detailed photo.
    final random = Random(7);
    final image = image_lib.Image(width: 2600, height: 1900);
    for (final pixel in image) {
      pixel
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    final dir = await Directory.systemTemp.createTemp('label_photo_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/big.jpg');
    await file.writeAsBytes(image_lib.encodeJpg(image, quality: 95));
    expect(await file.length(), greaterThan(maxLabelPhotoBytes));

    await compressLabelPhoto(file.path);

    expect(await file.length(), lessThanOrEqualTo(maxLabelPhotoBytes));
    expect(await labelPhotosFit([file.path, file.path, file.path, file.path]),
        isTrue);
    // Re-encoding a large worst-case photo several times is slow on a cold
    // test run; allow more than the default 30 seconds.
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('an unreadable file never fits instead of being sent', () async {
    expect(await labelPhotosFit(['does-not-exist.jpg']), isFalse);
  });
}
