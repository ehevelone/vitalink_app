// lib/screens/profile_manager_screen.dart
import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../models.dart';

class ProfileManagerScreen extends StatefulWidget {
  const ProfileManagerScreen({super.key});

  @override
  State<ProfileManagerScreen> createState() => _ProfileManagerScreenState();
}

class _ProfileManagerScreenState extends State<ProfileManagerScreen> {
  late final DataRepository _repo;
  List<Profile> _profiles = [];
  int _activeIndex = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final profiles = await _repo.loadAllProfiles();
    final activeIndex = await _repo.getActiveProfileIndex();
    setState(() {
      _profiles = profiles;
      _activeIndex = activeIndex;
      _loading = false;
    });
  }

  Future<void> _switch(int index) async {
    await _repo.setActiveProfileIndex(index);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _delete(int index) async {
    if (index == _activeIndex) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot delete the active profile")),
      );
      return;
    }

    final confirmed = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove Household Profile"),
        content: Text(
          "Are you sure you want to remove ${_profiles[index].fullName}? "
          "This cannot be undone.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete")),
        ],
      ),
    );

    if (confirmed != true) return;

    await _repo.deleteProfileAt(index);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Profile Manager")),
      body: ListView.builder(
        itemCount: _profiles.length,
        itemBuilder: (_, i) {
          final p = _profiles[i];
          final isActive = i == _activeIndex;

          return ListTile(
            tileColor: Colors.transparent,
            shape: const Border(
              bottom: BorderSide(color: Colors.black12),
            ),
            leading: Icon(
              isActive ? Icons.check_circle : Icons.person,
              color: isActive ? Colors.green : Colors.grey,
            ),
            title: Text(p.fullName.isNotEmpty ? p.fullName : "Unnamed Profile"),
            subtitle: Text(isActive ? "ACTIVE PROFILE" : "HOUSEHOLD MEMBER"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isActive)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz, color: Colors.blue),
                    tooltip: "Switch to this profile",
                    onPressed: () => _switch(i),
                  ),
                if (!isActive)
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    tooltip: "Delete Profile",
                    onPressed: () => _delete(i),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
