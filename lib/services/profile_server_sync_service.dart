import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import 'secure_store.dart';

class _PendingProfileSync {
  const _PendingProfileSync({
    required this.userId,
    required this.sessionToken,
    required this.profiles,
  });

  final String userId;
  final String sessionToken;
  final List<Map<String, dynamic>> profiles;
}

class ProfileServerSyncService {
  static const _url =
      'https://vitalink-app.netlify.app/.netlify/functions/save_user_profiles';
  static final Map<String, _PendingProfileSync> _pendingByUser = {};
  static Future<Map<String, dynamic>>? _drainFuture;

  static Future<Map<String, dynamic>> sync(List<Profile> profiles) async {
    final store = SecureStore();
    final userId = (await store.getString('userId') ?? '').trim();
    final sessionToken =
        (await store.getString('userSessionToken') ?? '').trim();
    if (userId.isEmpty || sessionToken.isEmpty) {
      return {'success': false, 'skipped': true};
    }

    final ownedProfiles = profiles
        .where(
          (profile) =>
              (profile.sharedRelationshipId == null ||
                  profile.sharedRelationshipId!.trim().isEmpty) &&
              profile.sharedAccessStatus == 'owned',
        )
        .map((profile) => profile.toJson())
        .toList();
    if (ownedProfiles.isEmpty) {
      return {'success': true, 'skipped': true};
    }

    _pendingByUser[userId] = _PendingProfileSync(
      userId: userId,
      sessionToken: sessionToken,
      profiles: ownedProfiles,
    );
    _drainFuture ??= _drain();
    return _drainFuture!;
  }

  static Future<Map<String, dynamic>> _drain() async {
    var lastResult = <String, dynamic>{'success': true};
    try {
      while (_pendingByUser.isNotEmpty) {
        // Coalesce rapid edits before taking the newest immutable snapshot.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final userId = _pendingByUser.keys.first;
        final pending = _pendingByUser.remove(userId)!;
        lastResult = await _send(pending);
      }
      return lastResult;
    } finally {
      _drainFuture = null;
      if (_pendingByUser.isNotEmpty) {
        _drainFuture = _drain();
      }
    }
  }

  static Future<Map<String, dynamic>> _send(
    _PendingProfileSync pending,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(_url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': pending.userId,
              'sessionToken': pending.sessionToken,
              'profiles': pending.profiles,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.body.isEmpty) {
        return {'success': false, 'httpStatus': response.statusCode};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return {
          ...Map<String, dynamic>.from(decoded),
          'httpStatus': response.statusCode,
        };
      }
      return {'success': false, 'httpStatus': response.statusCode};
    } on TimeoutException {
      debugPrint('PROFILE_SERVER_SYNC_TIMEOUT');
      return {'success': false, 'error': 'timeout'};
    } catch (error) {
      debugPrint('PROFILE_SERVER_SYNC_FAILED type=${error.runtimeType}');
      return {'success': false, 'error': error.runtimeType.toString()};
    }
  }
}
