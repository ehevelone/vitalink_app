import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart'; // ✅ needed for SecureStore

class DoctorsView extends StatefulWidget {
  const DoctorsView({super.key});

  @override
  State<DoctorsView> createState() => _DoctorsViewState();
}

class _DoctorsViewState extends State<DoctorsView> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore()); // ✅ consistent with other screens
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.loadProfile();
    setState(() {
      _p = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final docs = _p!.doctors;
    final title = _p?.fullName.isNotEmpty == true
        ? "Doctors – ${_p!.fullName}"
        : "Doctors";

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: docs.isEmpty
          ? const Center(
              child: Text(
                "No doctors available.",
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, i) {
                final d = docs[i];
                return ListTile(
                  tileColor: Colors.transparent,
                  shape: const Border(
                    bottom: BorderSide(color: Colors.black12),
                  ),
                  title: Text(
                    d.name.isNotEmpty ? d.name : "Unnamed Doctor",
                  ),
                  subtitle: Text(
                    [d.specialty, d.clinic, d.phone]
                        .where((s) => s.isNotEmpty)
                        .join(" • "),
                  ),
                );
              },
            ),
    );
  }
}
