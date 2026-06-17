// lib/screens/profile_picker_screen.dart
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  late final DataRepository _repo;
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
        title: const Text("Delete Profile"),
        content: Text("Permanently remove \"$name\" from household profiles?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await _repo.deleteProfileAt(index);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Switch Profile")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.add_link, color: Colors.blue),
                    title: const Text(
                      "Add Profile from Invite",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      "Use a profile share code from a family member or caregiver.",
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

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      tileColor: Colors.transparent,
                      shape: const Border(
                        bottom: BorderSide(color: Colors.black12),
                      ),
                      leading: Icon(
                        Icons.person,
                        color: isActive ? Colors.green : Colors.grey,
                        size: 32,
                      ),
                      title: Text(
                        p.fullName.isNotEmpty ? p.fullName : "Unnamed Profile",
                        style: const TextStyle(fontSize: 18),
                      ),
                      subtitle: isActive
                          ? const Text(
                              "Currently Active",
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                      onTap: () => _switchTo(index),
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
