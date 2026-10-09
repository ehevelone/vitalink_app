import 'dart:math' as math;
import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import 'edit_profile.dart';

class Formatters {
  static String phone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return raw;
    return "(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6, 10)}";
  }

  static String dob(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;

    return "${date.month.toString().padLeft(2, '0')}/"
        "${date.day.toString().padLeft(2, '0')}/"
        "${date.year}";
  }
}

class EmergencyView extends StatefulWidget {
  const EmergencyView({super.key});

  @override
  State<EmergencyView> createState() => _EmergencyViewState();
}

class _EmergencyViewState extends State<EmergencyView> {
  static const String _baseUrl = "https://myvitalink.app/emergency.html";

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
    if (!mounted) return;

    setState(() {
      _p = p;
      _loading = false;
    });
  }

  Widget _infoTile({
    required String title,
    required String subtitle,
    bool dense = false,
  }) {
    return ListTile(
      tileColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: Colors.black12),
      ),
      dense: dense,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _p == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.red),
        ),
      );
    }

    final p = _p!;
    final e = p.emergency;
    final qrToken = p.qrToken;

    if (qrToken == null || qrToken.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            AppStrings.of(context).qrTokenMissing,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    final qrUrl = "$_baseUrl?token=$qrToken";
    final qrSize = math
        .max(
          160.0,
          math.min(MediaQuery.sizeOf(context).width - 64, 280.0),
        )
        .toDouble();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        title: Text(
          AppStrings.of(context).emergencyInfoFor(p.fullName),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              ).then((_) => _load());
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (p.fullName.isNotEmpty)
            _infoTile(title: AppStrings.of(context).name, subtitle: p.fullName),
          if (p.dob?.isNotEmpty == true)
            _infoTile(
                title: AppStrings.of(context).dob,
                subtitle: Formatters.dob(p.dob!)),
          if (e.allergies.isNotEmpty)
            _infoTile(
                title: AppStrings.of(context).allergies, subtitle: e.allergies),
          if (e.conditions.isNotEmpty)
            _infoTile(
                title: AppStrings.of(context).conditions,
                subtitle: e.conditions),
          if (e.implants.isNotEmpty)
            _infoTile(
                title: AppStrings.of(context).implants, subtitle: e.implants),
          if (e.procedures.isNotEmpty)
            _infoTile(
                title: AppStrings.of(context).procedures,
                subtitle: e.procedures),
          _infoTile(
            title: AppStrings.of(context).dnrPolstOnFile,
            subtitle: e.dnrPolstOnFile
                ? '${AppStrings.of(context).yes}\n'
                    '${AppStrings.of(context).signedFormLocation}: '
                    '${e.dnrPolstLocation.isNotEmpty ? e.dnrPolstLocation : AppStrings.of(context).notProvided}'
                : AppStrings.of(context).no,
          ),
          if (e.dnrPolstOnFile)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                AppStrings.of(context).dnrPolstDisclaimer,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ...e.effectiveContacts.asMap().entries.map(
                (entry) => _infoTile(
                  title: AppStrings.of(context).emergencyContact(entry.key + 1),
                  subtitle: [
                    if (entry.value.name.isNotEmpty) entry.value.name,
                    if (entry.value.phone.isNotEmpty)
                      Formatters.phone(entry.value.phone),
                  ].join(" - "),
                ),
              ),
          const Divider(height: 32),
          if (p.meds.isNotEmpty) ...[
            Text(
              AppStrings.of(context).medications,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            ...p.meds.map(
              (m) => _infoTile(
                title: m.name,
                subtitle: [
                  if (m.dose.isNotEmpty) m.dose,
                  if (m.frequency.isNotEmpty) m.frequency,
                  if (m.servingSize.isNotEmpty)
                    '${AppStrings.of(context).servingLabel}: ${m.servingSize}',
                  if (m.activeIngredients.isNotEmpty)
                    '${AppStrings.of(context).supplementFactsLabel}: ${m.activeIngredients.take(3).join(", ")}',
                ].join(" - "),
                dense: true,
              ),
            ),
          ],
          if (p.doctors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              AppStrings.of(context).doctors,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            ...p.doctors.map(
              (d) => _infoTile(
                title: d.name,
                subtitle: d.phone,
                dense: true,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Center(
            child: SizedBox.square(
              dimension: qrSize,
              child: QrImageView(
                data: qrUrl,
                size: qrSize,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
