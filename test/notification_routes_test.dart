import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/services/notification_routes.dart';

void main() {
  test('every route the server sends in a notification is allowed', () {
    final routePattern = RegExp(r'''route["']?\s*:\s*["'](/[^"']+)["']''');
    final sent = <String>{};
    for (final entity in Directory('functions').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.js')) continue;
      if (entity.path.contains('node_modules')) continue;
      for (final match in routePattern.allMatches(entity.readAsStringSync())) {
        sent.add(match.group(1)!);
      }
    }

    expect(sent, isNotEmpty, reason: 'server route scan found nothing');
    expect(notificationRoutes, containsAll(sent));
  });

  test('every allowed notification route is registered in the app', () {
    final main = File('lib/main.dart').readAsStringSync();
    for (final route in notificationRoutes) {
      expect(main.contains("'$route':"), isTrue,
          reason: '$route is allowed but has no route in main.dart');
    }
  });

  test('unknown or missing routes are rejected', () {
    expect(isKnownNotificationRoute('/does_not_exist'), isFalse);
    expect(isKnownNotificationRoute(null), isFalse);
    expect(isKnownNotificationRoute('/authorization_form'), isTrue);
  });
}
