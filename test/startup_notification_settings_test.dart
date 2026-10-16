import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/main.dart';

void main() {
  test('startup notification settings include Android and iOS', () {
    final settings = notificationInitializationSettings();

    expect(settings.android, isNotNull);
    expect(settings.iOS, isNotNull);
  });
}
