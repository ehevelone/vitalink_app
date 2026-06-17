import 'package:flutter/foundation.dart';

import '../models.dart';
import 'api_service.dart';
import 'secure_store.dart';

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
      return ApiService.createProfileUpdatePackage(
        userId: userId,
        profileId: profile.id,
        profileName: profile.fullName,
        allowedSections: sections,
        payload: buildPayload(profile, sections: sections),
      );
    } catch (e) {
      debugPrint('Profile update publish failed: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
