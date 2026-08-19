import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart'; // ✅ Needed for SecureStore

class MedsView extends StatefulWidget {
  const MedsView({super.key});

  @override
  State<MedsView> createState() => _MedsViewState();
}

class _MedsViewState extends State<MedsView> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.loadProfile();
    setState(() {
      _p = p;
      _loading = false;
    });
  }

  String _supplementPreview(Medication m) {
    final parts = <String>[
      if (m.dose.isNotEmpty) m.dose,
      if (m.frequency.isNotEmpty) m.frequency,
      if (m.servingSize.isNotEmpty) 'Serving: ${m.servingSize}',
      if (m.activeIngredients.isNotEmpty)
        'Supplement Facts: ${m.activeIngredients.take(3).join(", ")}',
    ];
    return parts.join(" • ");
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final meds = _p!.meds;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Medications${_p?.fullName.isNotEmpty == true ? " – ${_p!.fullName}" : ""}",
        ),
      ),
      body: meds.isEmpty
          ? const Center(
              child: Text(
                "No medications available.",
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: meds.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = meds[i];
                final subtitle = m.isSupplementOrOtc
                    ? _supplementPreview(m)
                    : [m.dose, m.frequency, m.prescriber]
                        .where((s) => s.isNotEmpty)
                        .join(" • ");
                return ListTile(
                  tileColor: Colors.transparent,
                  shape: const Border(
                    bottom: BorderSide(color: Colors.black12),
                  ),
                  leading: Icon(
                    m.isSupplementOrOtc
                        ? Icons.spa_outlined
                        : Icons.medication_outlined,
                  ),
                  title:
                      Text(m.name.isNotEmpty ? m.name : "Unnamed Medication"),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                );
              },
            ),
    );
  }
}
