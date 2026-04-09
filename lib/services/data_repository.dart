import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'secure_store.dart';

class DataRepository {
  final SecureStore _store;

  // ✅ KEEP compatibility
  DataRepository([SecureStore? store]) : _store = store ?? SecureStore();

  static const String _profilesKey = 'profiles_json';
  static const String _activeIndexKey = 'active_profile_index';

  // ==========================================================
  // INTERNAL LOAD
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
            // skip bad entry only
          }
        }

        return profiles;
      }
    } catch (_) {
      // fail safe — no wipe
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
  // 🔥 NAME SYNC
  // ==========================================================
  Future<void> _syncName(Profile p) async {
    final name = (p.fullName).trim();

    if (name.isNotEmpty) {
      await _store.setString("userName", name);
    }
  }

  // ==========================================================
  // PUBLIC API
  // ==========================================================

  // 🔥 FIXED + SELF-HEALING PROFILE LOAD
  Future<Profile> loadProfile() async {
    final list = await _loadProfilesInternal();

    // Create profile if none exists
    if (list.isEmpty) {
      final newProfile = Profile();
      await addProfile(newProfile);
      return newProfile;
    }

    final idx = await _getActiveIndex(list);
    final p = list[idx];

    // ==========================================================
    // 🔥 CRITICAL FIX — VALIDATE ID
    // ==========================================================
    if (p.id.isEmpty || p.id.length < 30) {
      print("🚨 INVALID PROFILE ID DETECTED → RESETTING");

      final newProfile = Profile(); // generates proper UUID
      await saveProfile(newProfile);

      await _syncName(newProfile);
      return newProfile;
    }

    // ==========================================================
    // EXISTING LOGIC (UNCHANGED)
    // ==========================================================
    final name = p.fullName.trim();

    if (name.isNotEmpty) {
      await saveProfile(p); // forces clean rewrite
    }

    // 🔥 always sync name to backup storage
    await _syncName(p);

    return p;
  }

  Future<List<Profile>> loadAllProfiles() async {
    return _loadProfilesInternal();
  }

  Future<void> saveProfile(Profile profile) async {
    final profiles = await _loadProfilesInternal();

    if (profiles.isEmpty) {
      await _saveProfilesInternal([profile], activeIndex: 0);
      await _syncName(profile);
      return;
    }

    final idx = await _getActiveIndex(profiles);
    final updated = List<Profile>.from(profiles);
    updated[idx] = profile;

    await _saveProfilesInternal(updated, activeIndex: idx);

    // 🔥 sync name after save
    await _syncName(profile);
  }

  Future<void> addProfile(Profile profile) async {
    final profiles = await _loadProfilesInternal();

    final updated = [...profiles, profile];
    final newIndex = updated.length - 1;

    await _saveProfilesInternal(updated, activeIndex: newIndex);

    // 🔥 sync new profile name
    await _syncName(profile);
  }

  Future<void> setActiveProfileIndex(int index) async {
    final profiles = await _loadProfilesInternal();
    if (profiles.isEmpty) return;
    if (index < 0 || index >= profiles.length) return;

    await _saveProfilesInternal(profiles, activeIndex: index);

    // 🔥 sync newly active profile name
    final p = profiles[index];
    await _syncName(p);
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

    // 🔥 sync new active profile
    if (profiles.isNotEmpty) {
      await _syncName(profiles[newActive]);
    }
  }
}