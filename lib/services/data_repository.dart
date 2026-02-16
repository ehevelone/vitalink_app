// lib/services/data_repository.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'secure_store.dart'; // keep for compatibility with existing calls

class DataRepository {
  // ✅ Compatibility constructor (prevents 40 screen errors)
  DataRepository([SecureStore? _]);

  static const String _profilesKey = 'profiles_json';
  static const String _activeIndexKey = 'active_profile_index';

  // ==========================================================
  // INTERNAL LOAD (SAFE — NO STORAGE WIPE)
  // ==========================================================
  Future<List<Profile>> _loadProfilesInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);

    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);

      if (decoded is List) {
        final profiles = <Profile>[];

        for (final item in decoded) {
          try {
            profiles.add(
              Profile.fromJson(
                Map<String, dynamic>.from(item),
              ),
            );
          } catch (_) {
            // Skip corrupted profile entry ONLY
          }
        }

        return profiles;
      }
    } catch (_) {
      // ❗ DO NOT DELETE STORAGE
      // Just fail gracefully
    }

    return [];
  }

  // ==========================================================
  // INTERNAL SAVE
  // ==========================================================
  Future<void> _saveProfilesInternal(
    List<Profile> profiles, {
    int? activeIndex,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final list = profiles.map((p) => p.toJson()).toList();
    await prefs.setString(_profilesKey, jsonEncode(list));

    if (activeIndex != null) {
      await prefs.setInt(_activeIndexKey, activeIndex);
    }
  }

  // ==========================================================
  // ACTIVE INDEX
  // ==========================================================
  Future<int> _getActiveIndex(List<Profile> profiles) async {
    final prefs = await SharedPreferences.getInstance();

    if (profiles.isEmpty) return 0;

    int idx = prefs.getInt(_activeIndexKey) ?? 0;

    if (idx < 0 || idx >= profiles.length) idx = 0;
    return idx;
  }

  // ==========================================================
  // PUBLIC API
  // ==========================================================
  Future<Profile?> loadProfile() async {
    final list = await _loadProfilesInternal();
    if (list.isEmpty) return null;

    final idx = await _getActiveIndex(list);
    return list[idx];
  }

  Future<List<Profile>> loadAllProfiles() async {
    return _loadProfilesInternal();
  }

  Future<void> saveProfile(Profile profile) async {
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
