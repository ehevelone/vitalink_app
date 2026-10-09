import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models.dart';
import 'persistent_file_store.dart';
import 'profile_server_sync_service.dart';
import 'profile_update_sync_service.dart';
import 'secure_store.dart';
import '../l10n/app_strings.dart';
import '../l10n/screen_strings.dart';

class DataRepository {
  final SecureStore _store;

  // ✅ KEEP compatibility
  DataRepository([SecureStore? store]) : _store = store ?? SecureStore();

  static const String _profilesKey = 'profiles_json';
  static const String _activeIndexKey = 'active_profile_index';

  Future<String> _accountSuffix() async {
    final userId = (await _store.getString('userId') ?? '').trim();
    final userSession =
        (await _store.getString('userSessionToken') ?? '').trim();
    if (userId.isNotEmpty && userSession.isNotEmpty) {
      return 'user_${userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
    }

    final agentId = (await _store.getString('agentId') ?? '').trim();
    final agentSession =
        (await _store.getString('agentSessionToken') ?? '').trim();
    if (agentId.isNotEmpty && agentSession.isNotEmpty) {
      return 'agent_${agentId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
    }

    return 'unassigned';
  }

  Future<String> _accountProfilesKey() async =>
      '${_profilesKey}_${await _accountSuffix()}';

  Future<String> _accountActiveIndexKey() async =>
      '${_activeIndexKey}_${await _accountSuffix()}';

  Future<String> currentStorageSuffix() => _accountSuffix();

  // ==========================================================
  // INTERNAL LOAD
  // ==========================================================
  Future<List<Profile>> _loadProfilesInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final accountSuffix = await _accountSuffix();
    final profilesKey = '${_profilesKey}_$accountSuffix';
    var raw = await _store.getString(profilesKey);

    // Compatibility for the short-lived account key used by build 313a4a6.
    // It was never released, but retaining this read protects test devices.
    if ((raw == null || raw.isEmpty) && accountSuffix.startsWith('user_')) {
      final rawUserId = accountSuffix.substring('user_'.length);
      final interimProfilesKey = '${_profilesKey}_$rawUserId';
      final interimIndexKey = '${_activeIndexKey}_$rawUserId';
      final interimRaw = await _store.getString(interimProfilesKey);
      if (interimRaw != null && interimRaw.isNotEmpty) {
        raw = interimRaw;
        await _store.setString(profilesKey, interimRaw);
        final interimIndex = await _store.getString(interimIndexKey);
        if (interimIndex != null && interimIndex.isNotEmpty) {
          await _store.setString(
            '${_activeIndexKey}_$accountSuffix',
            interimIndex,
          );
        }
        await _store.remove(interimProfilesKey);
        await _store.remove(interimIndexKey);
      }
    }

    // Device-wide legacy data may contain client medical profiles. Never move
    // it into an agent account merely because the agent logs in first.
    if ((raw == null || raw.isEmpty) && accountSuffix.startsWith('user_')) {
      final legacySecure = await _store.getString(_profilesKey);
      final legacyPrefs = prefs.getString(_profilesKey);
      final legacyRaw =
          (legacySecure?.isNotEmpty ?? false) ? legacySecure : legacyPrefs;
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        final currentUserId = (await _store.getString('userId') ?? '').trim();
        final recordedOwner =
            (await _store.getString('profileOwnerUserId') ?? '').trim();
        final migrationOwner = recordedOwner.isNotEmpty
            ? 'user_${recordedOwner.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}'
            : accountSuffix;
        final migrationProfilesKey = '${_profilesKey}_$migrationOwner';
        final migrationIndexKey = '${_activeIndexKey}_$migrationOwner';
        await _store.setString(migrationProfilesKey, legacyRaw);

        final legacyIndex = await _store.getString(_activeIndexKey) ??
            prefs.getInt(_activeIndexKey)?.toString();
        if (legacyIndex != null && legacyIndex.isNotEmpty) {
          await _store.setString(migrationIndexKey, legacyIndex);
        }
        await _store.remove(_profilesKey);
        await _store.remove(_activeIndexKey);
        await prefs.remove(_profilesKey);
        await prefs.remove(_activeIndexKey);

        if (recordedOwner.isEmpty || recordedOwner == currentUserId) {
          raw = legacyRaw;
        }
      }
    }

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

        var migratedIds = false;
        for (final profile in profiles) {
          if (profile.id.isEmpty) {
            profile.id = const Uuid().v4();
            migratedIds = true;
          } else if (profile.id.length < 30) {
            profile.id = const Uuid().v5(Uuid.NAMESPACE_URL, profile.id);
            migratedIds = true;
          }
        }
        if (migratedIds) {
          await _saveProfilesInternal(profiles);
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
    bool syncToServer = true,
  }) async {
    final list = profiles.map((p) => p.toJson()).toList();
    await _store.setString(await _accountProfilesKey(), jsonEncode(list));

    if (activeIndex != null) {
      await _store.setString(
        await _accountActiveIndexKey(),
        activeIndex.toString(),
      );
    }

    if (syncToServer) {
      unawaited(ProfileServerSyncService.sync(profiles));
    }
  }

  // ==========================================================
  // ACTIVE INDEX
  // ==========================================================
  Future<int> _getActiveIndex(List<Profile> profiles) async {
    if (profiles.isEmpty) return 0;

    int idx = int.tryParse(
          await _store.getString(await _accountActiveIndexKey()) ?? '',
        ) ??
        0;

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

    // Keep the local account display name aligned with the active profile.
    await _syncName(p);

    return p;
  }

  Future<List<Profile>> loadAllProfiles() async {
    return _loadProfilesInternal();
  }

  Future<Map<String, dynamic>> exportDeviceTransferPayload() async {
    final profiles = await _loadProfilesInternal();
    final activeIndex = await _getActiveIndex(profiles);

    return {
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'activeProfileIndex': activeIndex,
      'profiles': profiles.map((p) => p.toJson()).toList(),
    };
  }

  Future<void> importDeviceTransferPayload(
    Map<String, dynamic> payload,
  ) async {
    final rawProfiles = payload['profiles'];

    if (rawProfiles is! List || rawProfiles.isEmpty) {
      throw Exception(AppStrings.current().noProfilesInTransfer);
    }

    final profiles = <Profile>[];

    for (final item in rawProfiles) {
      if (item is Map) {
        profiles.add(Profile.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    if (profiles.isEmpty) {
      throw Exception(AppStrings.current().noProfilesInTransfer);
    }

    final rawIndex = payload['activeProfileIndex'];
    final importedActive = profiles[
        rawIndex is int ? rawIndex.clamp(0, profiles.length - 1).toInt() : 0];

    // Merge rather than overwrite: keep anything already entered on this
    // phone, let transferred copies replace same-id profiles, and drop the
    // empty placeholder profile the app creates on first launch.
    final importedIds = profiles.map((p) => p.id).toSet();
    final existing = await _loadProfilesInternal();
    final kept = existing
        .where((p) => !importedIds.contains(p.id) && !_isEmptyPlaceholder(p))
        .toList();
    final merged = [...kept, ...profiles];
    final activeIndex = merged.indexWhere((p) => p.id == importedActive.id);

    await _saveProfilesInternal(merged, activeIndex: activeIndex);
    await _syncName(importedActive);
  }

  bool _isEmptyPlaceholder(Profile p) =>
      p.fullName.trim().isEmpty &&
      p.meds.isEmpty &&
      p.doctors.isEmpty &&
      p.appointments.isEmpty &&
      p.insurances.isEmpty &&
      p.orphanCards.isEmpty &&
      jsonEncode(p.emergency.toJson()) == jsonEncode(EmergencyInfo().toJson());

  Future<void> saveProfile(
    Profile profile, {
    bool publishUpdate = true,
  }) async {
    final profiles = await _loadProfilesInternal();

    if (profiles.isEmpty) {
      await _saveProfilesInternal([profile], activeIndex: 0);
      await _syncName(profile);
      if (publishUpdate) {
        _publishSharedUpdate(profile);
      }
      return;
    }

    final idx = await _getActiveIndex(profiles);
    final updated = List<Profile>.from(profiles);
    updated[idx] = profile;

    await _saveProfilesInternal(updated, activeIndex: idx);

    // 🔥 sync name after save
    await _syncName(profile);

    if (publishUpdate) {
      _publishSharedUpdate(profile);
    }
  }

  void _publishSharedUpdate(Profile profile) {
    unawaited(
      ProfileUpdateSyncService()
          .publishProfileUpdate(profile)
          .catchError((_) => <String, dynamic>{'success': false}),
    );
  }

  Future<void> applySharedProfileUpdate(
    Map<String, dynamic> updatePayload,
  ) async {
    updatePayload =
        await PersistentFileStore.restoreProfileFileBytes(updatePayload);

    final profileMap =
        Map<String, dynamic>.from(updatePayload['profile'] as Map? ?? {});

    final profileId = (profileMap['id'] ?? updatePayload['profileId'] ?? '')
        .toString()
        .trim();

    if (profileId.isEmpty) return;

    final profiles = await _loadProfilesInternal();
    final idx = profiles.indexWhere((p) => p.id == profileId);

    final current = idx >= 0
        ? profiles[idx]
        : Profile(
            id: profileId,
            fullName: (profileMap['fullName'] ??
                    updatePayload['profileName'] ??
                    'Shared Profile')
                .toString(),
          );

    final updated = current.copyWith(
      sharedRelationshipId: updatePayload['_shareRelationshipId']?.toString() ??
          current.sharedRelationshipId,
      sharedAccessStatus: 'active',
      fullName: profileMap['fullName'] ?? current.fullName,
      dob: profileMap['dob'] ?? current.dob,
      userPhone: profileMap['userPhone'] ?? current.userPhone,
      address: profileMap['address'] ?? current.address,
      city: profileMap['city'] ?? current.city,
      state: profileMap['state'] ?? current.state,
      zip: profileMap['zip'] ?? current.zip,
      updatedAt: DateTime.now(),
      emergency: updatePayload['emergency'] is Map
          ? EmergencyInfo.fromJson(
              Map<String, dynamic>.from(updatePayload['emergency'] as Map),
            )
          : current.emergency,
      meds: updatePayload['meds'] is List
          ? (updatePayload['meds'] as List)
              .whereType<Map>()
              .map((m) => Medication.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : current.meds,
      doctors: updatePayload['doctors'] is List
          ? (updatePayload['doctors'] as List)
              .whereType<Map>()
              .map((d) => Doctor.fromJson(Map<String, dynamic>.from(d)))
              .toList()
          : current.doctors,
      appointments: updatePayload['appointments'] is List
          ? (updatePayload['appointments'] as List)
              .whereType<Map>()
              .map(
                  (a) => UserAppointment.fromJson(Map<String, dynamic>.from(a)))
              .toList()
          : current.appointments,
      insurances: updatePayload['insurances'] is List
          ? (updatePayload['insurances'] as List)
              .whereType<Map>()
              .map((i) => Insurance.fromJson(Map<String, dynamic>.from(i)))
              .toList()
          : current.insurances,
      orphanCards: updatePayload['orphanCards'] is List
          ? (updatePayload['orphanCards'] as List)
              .whereType<Map>()
              .map((c) => InsuranceCard.fromJson(Map<String, dynamic>.from(c)))
              .toList()
          : current.orphanCards,
    );

    if (idx >= 0) {
      profiles[idx] = updated;
      await _saveProfilesInternal(profiles);
    } else {
      final updatedProfiles = [...profiles, updated];
      await _saveProfilesInternal(
        updatedProfiles,
        activeIndex: updatedProfiles.length - 1,
      );
    }

    await _syncName(updated);
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

    await _saveProfilesInternal(
      profiles,
      activeIndex: index,
      syncToServer: false,
    );

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

    await _deleteProfileFiles(profiles[index]);
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

  Future<void> _deleteProfileFiles(Profile profile) async {
    final paths = <String>{};
    void collect(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          final child = entry.value;
          if (key == 'imagePath' ||
              key == 'frontImagePath' ||
              key == 'backImagePath' ||
              key == 'decPagePaths') {
            if (child is String && child.isNotEmpty) paths.add(child);
            if (child is List) {
              paths
                  .addAll(child.whereType<String>().where((p) => p.isNotEmpty));
            }
          }
          collect(child);
        }
      } else if (value is List) {
        for (final item in value) {
          collect(item);
        }
      }
    }

    collect(profile.toJson());
    for (final path in paths) {
      await PersistentFileStore.deleteIfLocal(path);
    }
    await _store.remove('qr_url:${profile.id}');
  }

  Future<void> clearLocalProfiles({String? storageSuffix}) async {
    final suffix = storageSuffix ?? await _accountSuffix();
    final profilesKey = '${_profilesKey}_$suffix';
    final activeIndexKey = '${_activeIndexKey}_$suffix';
    final raw = await _store.getString(profilesKey);
    final profiles = <Profile>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            profiles.add(Profile.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      } catch (_) {
        // Continue removing the account keys even if one record is malformed.
      }
    }
    final paths = <String>{};

    void collect(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          final child = entry.value;
          if (key == 'imagePath' ||
              key == 'frontImagePath' ||
              key == 'backImagePath' ||
              key == 'decPagePaths') {
            if (child is String && child.isNotEmpty) paths.add(child);
            if (child is List) {
              paths
                  .addAll(child.whereType<String>().where((p) => p.isNotEmpty));
            }
          }
          collect(child);
        }
      } else if (value is List) {
        for (final item in value) {
          collect(item);
        }
      }
    }

    collect(profiles.map((p) => p.toJson()).toList());
    for (final path in paths) {
      await PersistentFileStore.deleteIfLocal(path);
    }
    for (final profile in profiles) {
      await _store.remove('qr_url:${profile.id}');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(profilesKey);
    await prefs.remove(activeIndexKey);
    await _store.remove(profilesKey);
    await _store.remove(activeIndexKey);
    await _store.remove('userName');
    await _store.remove('qr_url');
  }

  Future<void> applySharedAccessStatuses(
    List<Map<String, dynamic>> relationships,
  ) async {
    final profiles = await _loadProfilesInternal();
    var changed = false;
    for (var i = 0; i < profiles.length; i += 1) {
      final relationshipId = profiles[i].sharedRelationshipId;
      if (relationshipId == null || relationshipId.isEmpty) continue;
      final match = relationships.cast<Map<String, dynamic>?>().firstWhere(
            (item) => item?['shareId']?.toString() == relationshipId,
            orElse: () => null,
          );
      if (match == null) continue;
      final status = match['status']?.toString() ?? 'revoked';
      final nextStatus = status == 'accepted' ? 'active' : 'revoked';
      if (profiles[i].sharedAccessStatus != nextStatus) {
        profiles[i] = profiles[i].copyWith(sharedAccessStatus: nextStatus);
        changed = true;
      }
    }
    if (changed) await _saveProfilesInternal(profiles);
  }
}
