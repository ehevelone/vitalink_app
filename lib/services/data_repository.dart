// lib/services/data_repository.dart
import 'dart:convert';

import 'secure_store.dart';
import '../models.dart';

class DataRepository {
  final SecureStore _store;

  static const String _profilesKey = 'profiles_json';
  static const String _activeIndexKey = 'active_profile_index';

  DataRepository(this._store);

  // ---------- Internal helpers ----------
  Future<List<Profile>> _loadProfilesInternal() async {
    final raw = await _store.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);

      if (decoded is List) {
        final profiles = <Profile>[];

        for (final item in decoded) {
          try {
            profiles.add(
              Profile.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            );
          } catch (_) {
            // Skip corrupted profile entry
          }
        }

        return profiles;
      }
    } catch (_) {
      // Entire JSON corrupted → auto-heal
      await _store.delete(_profilesKey);
      await _store.delete(_activeIndexKey);
    }

    return [];
  }

  Future<void> _saveProfilesInternal(
    List<Profile> profiles, {
    int? activeIndex,
  }) async {
    try {
      final list = profiles.map((p) => p.toJson()).toList();
      await _store.setString(_profilesKey, jsonEncode(list));

      if (activeIndex != null) {
        await _store.setString(_activeIndexKey, activeIndex.toString());
      }
    } catch (_) {
      // If save fails, clear corrupted data
      await _store.delete(_profilesKey);
      await _store.delete(_activeIndexKey);
    }
  }

  Future<int> _getActiveIndex(List<Profile> profiles) async {
    if (profiles.isEmpty) return 0;

    final raw = await _store.getString(_activeIndexKey);
    int idx = int.tryParse(raw ?? '') ?? 0;

    if (idx < 0 || idx >= profiles.length) idx = 0;
    return idx;
  }

  // ---------- MIGRATION: pull legacy profile from original secure keys ----------
  Future<void> _migrateLegacyIfNeeded() async {
    final list = await _loadProfilesInternal();
    if (list.isNotEmpty) return;

    final name = await _store.getString("userName");
    final phone = await _store.getString("userPhone");
    final emergencyContact = await _store.getString("emergencyContact");
    final emergencyPhone = await _store.getString("emergencyPhone");
    final allergies = await _store.getString("emergencyAllergies");
    final conditions = await _store.getString("emergencyConditions");
    final blood = await _store.getString("emergencyBloodType");

    if (name == null || name.isEmpty) return;

    final legacy = Profile(
      fullName: name,
      emergency: EmergencyInfo(
        contact: emergencyContact ?? "",
        phone: emergencyPhone ?? phone ?? "",
        allergies: allergies ?? "",
        conditions: conditions ?? "",
        bloodType: blood ?? "",
      ),
    );

    await _saveProfilesInternal([legacy], activeIndex: 0);
  }

  // ---------- PUBLIC API ----------
  Future<Profile?> loadProfile() async {
    await _migrateLegacyIfNeeded();
    final list = await _loadProfilesInternal();
    if (list.isEmpty) return null;

    final idx = await _getActiveIndex(list);
    return list[idx];
  }

  Future<List<Profile>> loadAllProfiles() async {
    await _migrateLegacyIfNeeded();
    return _loadProfilesInternal();
  }

  Future<void> saveProfile(Profile profile) async {
    await _migrateLegacyIfNeeded();
    final profiles = await _loadProfilesInternal();

    if (profiles.isEmpty) {
      await _saveProfilesInternal([profile], activeIndex: 0);
      return;
    }

    final idx = await _getActiveIndex(profiles);
    final updated = List<Profile>.from(profiles);
    updated[idx] = profile;

    await _saveProfilesInternal(updated, activeIndex: idx);
  }

  Future<void> addProfile(Profile profile) async {
    await _migrateLegacyIfNeeded();
    final profiles = await _loadProfilesInternal();
    final updated = [...profiles, profile];
    final newIndex = updated.length - 1;

    await _saveProfilesInternal(updated, activeIndex: newIndex);
  }

  Future<void> setActiveProfileIndex(int index) async {
    final profiles = await _loadProfilesInternal();
    if (profiles.isEmpty) return;
    if (index < 0 || index >= profiles.length) return;

    await _saveProfilesInternal(profiles, activeIndex: index);
  }

  Future<int> getActiveProfileIndex() async {
    final profiles = await _loadProfilesInternal();
    if (profiles.isEmpty) return 0;

    return _getActiveIndex(profiles);
  }

  Future<void> deleteProfileAt(int index) async {
    final profiles = await _loadProfilesInternal();
    if (index < 0 || index >= profiles.length) return;

    profiles.removeAt(index);

    int newActive = 0;
    if (profiles.isNotEmpty) {
      newActive = index.clamp(0, profiles.length - 1);
    }

    await _saveProfilesInternal(profiles, activeIndex: newActive);
  }
}
