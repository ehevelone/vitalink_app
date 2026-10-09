import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

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
          _p?.fullName.isNotEmpty == true
              ? AppStrings.of(context).medicationsFor(_p!.fullName)
              : AppStrings.of(context).medications,
        ),
      ),
      body: meds.isEmpty
          ? Center(
              child: Text(
                AppStrings.of(context).noMedicationsAvailable,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: meds.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = meds[i];
                final subtitle = m.isSupplementOrOtc
                    ? [
                        if (m.dose.isNotEmpty) m.dose,
                        if (m.frequency.isNotEmpty) m.frequency,
                        if (m.servingSize.isNotEmpty)
                          '${AppStrings.of(context).servingLabel}: ${m.servingSize}',
                        if (m.activeIngredients.isNotEmpty)
                          '${AppStrings.of(context).supplementFactsLabel}: ${m.activeIngredients.take(3).join(", ")}',
                      ].join(" • ")
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
                  title: Text(m.name.isNotEmpty
                      ? m.name
                      : AppStrings.of(context).unnamedMedication),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                );
              },
            ),
    );
  }
}
