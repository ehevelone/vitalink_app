// lib/screens/profile_picker_screen.dart
import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../models.dart';

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
    await _load(); // refresh UI
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Switch Profile")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _profiles.length,
              itemBuilder: (_, index) {
                final p = _profiles[index];
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
                                fontWeight: FontWeight.w600),
                          )
                        : null,
                    onTap: () => _switchTo(index),

                    // 🔥 delete button always available
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _delete(index),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
