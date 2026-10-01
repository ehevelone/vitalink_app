import 'package:flutter/foundation.dart';

import '../models.dart';
import 'api_service.dart';
import 'persistent_file_store.dart';
import 'secure_store.dart';
import 'profile_share_crypto_service.dart';

class ProfileUpdateSyncService {
  static const List<String> defaultSections = [
    'emergency',
    'medications',
    'doctors',
    'insurance_cards',
    'policies',
    'appointments',
  ];

  final SecureStore _store;
  final ProfileShareCryptoService _crypto = ProfileShareCryptoService();

  ProfileUpdateSyncService([SecureStore? store])
      : _store = store ?? SecureStore();

  Map<String, dynamic> buildPayload(
    Profile profile, {
    List<String> sections = defaultSections,
  }) {
    final selected = sections.toSet();

    return {
      'profileId': profile.id,
      'profileName': profile.fullName,
      'updatedAt': DateTime.now().toIso8601String(),
      'profile': {
        'id': profile.id,
        'fullName': profile.fullName,
        'dob': profile.dob,
        'userPhone': profile.userPhone,
        'address': profile.address,
        'city': profile.city,
        'state': profile.state,
        'zip': profile.zip,
      },
      if (selected.contains('emergency'))
        'emergency': profile.emergency.toJson(),
      if (selected.contains('medications'))
        'meds': profile.meds.map((m) => m.toJson()).toList(),
      if (selected.contains('doctors'))
        'doctors': profile.doctors.map((d) => d.toJson()).toList(),
      if (selected.contains('appointments'))
        'appointments': profile.appointments.map((a) => a.toJson()).toList(),
      if (selected.contains('policies'))
        'insurances': profile.insurances.map((i) => i.toJson()).toList(),
      if (selected.contains('insurance_cards'))
        'orphanCards': profile.orphanCards.map((c) => c.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> publishProfileUpdate(
    Profile profile, {
    List<String> sections = defaultSections,
  }) async {
    final userId = await _store.getString('userId');

    if (userId == null || userId.isEmpty) {
      return {'success': false, 'error': 'Missing user'};
    }

    try {
      final sharesResult = await ApiService.getProfileShareLinks(
        userId: userId,
        profileId: profile.id,
      );
      final shares = sharesResult['shares'] is List
          ? (sharesResult['shares'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => item['status']?.toString() == 'accepted')
              .toList()
          : <Map<String, dynamic>>[];
      final packages = <Map<String, dynamic>>[];

      for (final share in shares) {
        final shareId = share['id']?.toString() ?? '';
        final key = shareId.isEmpty ? null : await _crypto.loadKey(shareId);
        if (key == null || key.isEmpty) continue;
        final allowed = (share['allowed_sections'] as List? ?? const [])
            .map((item) => item.toString())
            .where(sections.contains)
            .toList();
        if (allowed.isEmpty) continue;
        final payload = await PersistentFileStore.attachProfileFileBytes(
          buildPayload(profile, sections: allowed),
        );
        packages.add({
          'shareId': shareId,
          'allowedSections': allowed,
          'encryptedPayload': await _crypto.encryptJson({
            'profileId': profile.id,
            'profileName': profile.fullName,
            'allowedSections': allowed,
            'payload': payload,
            'createdAt': DateTime.now().toIso8601String(),
          }, key),
        });
      }

      if (packages.isEmpty) {
        return {'success': true, 'recipients': 0};
      }
      return ApiService.createProfileUpdatePackage(
        userId: userId,
        profileId: profile.id,
        profileName: profile.fullName,
        packages: packages,
      );
    } catch (e) {
      debugPrint('Profile update publish failed: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
