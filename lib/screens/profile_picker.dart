// lib/screens/profile_picker_screen.dart
import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

import '../models.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/profile_share_crypto_service.dart';
import '../services/secure_store.dart';

class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  late final DataRepository _repo;
  final SecureStore _store = SecureStore();
  final ProfileShareCryptoService _crypto = ProfileShareCryptoService();
  List<Profile> _profiles = [];
  int _active = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.loadAllProfiles();
    final activeIdx = await _repo.getActiveProfileIndex();

    if (!mounted) return;
    setState(() {
      _profiles = list;
      _active = activeIdx;
      _loading = false;
    });
  }

  Future<void> _switchTo(int index) async {
    await _repo.setActiveProfileIndex(index);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _delete(int index) async {
    final name = _profiles[index].fullName;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.of(context).deleteProfile),
        content: Text(AppStrings.of(context).permanentlyRemoveProfile(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).delete),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final shareId = _profiles[index].sharedRelationshipId;
    if (shareId != null && shareId.isNotEmpty) {
      final userId = await _store.getString('userId');
      if (userId != null && userId.isNotEmpty) {
        await ApiService.removeSharedProfileCopy(
          userId: userId,
          shareId: shareId,
        );
      }
      await _crypto.deleteKey(shareId);
    }
    await _repo.deleteProfileAt(index);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).switchProfile)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.add_link, color: Colors.blue),
                    title: Text(
                      AppStrings.of(context).addProfileFromInvite,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      AppStrings.of(context).useProfileShareCode,
                    ),
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/profile_accept',
                    ).then((_) => _load()),
                  ),
                ),
                const SizedBox(height: 10),
                ..._profiles.asMap().entries.map((entry) {
                  final index = entry.key;
                  final p = entry.value;
                  final isActive = index == _active;
                  final sharingEnded = p.sharedAccessStatus == 'revoked';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      tileColor: sharingEnded
                          ? Colors.grey.shade200
                          : Colors.transparent,
                      shape: const Border(
                        bottom: BorderSide(color: Colors.black12),
                      ),
                      leading: Icon(
                        Icons.person,
                        color: sharingEnded
                            ? Colors.grey
                            : (isActive ? Colors.green : Colors.grey),
                        size: 32,
                      ),
                      title: Text(
                        p.fullName.isNotEmpty
                            ? p.fullName
                            : AppStrings.of(context).unnamedProfile,
                        style: TextStyle(
                          fontSize: 18,
                          color: sharingEnded ? Colors.grey.shade600 : null,
                        ),
                      ),
                      subtitle: sharingEnded
                          ? Text(
                              AppStrings.of(context).sharingEndedCopy,
                              style: const TextStyle(color: Colors.redAccent),
                            )
                          : isActive
                              ? Text(
                                  AppStrings.of(context).currentlyActive,
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                      onTap: sharingEnded ? null : () => _switchTo(index),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _delete(index),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
