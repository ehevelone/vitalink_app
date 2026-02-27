import 'dart:io';

class CardCropper {
  /// iOS build version:
  /// MLKit removed completely.
  /// Simply returns original file without auto-cropping.
  static Future<File?> autoCropCard(File file) async {
    try {
      return file;
    } catch (_) {
      return null;
    }
  }
}