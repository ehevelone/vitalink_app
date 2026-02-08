import 'dart:convert';
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
    try {
      final date = DateTime.tryParse(raw);
      if (date != null) {
        return "${date.month.toString().padLeft(2, '0')}/"
            "${date.day.toString().padLeft(2, '0')}/"
            "${date.year}";
      }
    } catch (_) {}
    return raw;
  }
}

class EmergencyView extends StatefulWidget {
  const EmergencyView({super.key});

  @override
  State<EmergencyView> createState() => _EmergencyViewState();
}

class _EmergencyViewState extends State<EmergencyView> {
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
        body: Center(
          child: CircularProgressIndicator(color: Colors.red),
        ),
      );
    }

    final p = _p!;
    final e = p.emergency;

    final qrData = jsonEncode({
      "name": p.fullName,
      "dob": p.dob ?? "",
      "allergies": e.allergies,
      "conditions": e.conditions,
      "emergencyContactName": e.contact,
      "emergencyContactPhone": e.phone,
      "meds": p.meds
          .map((m) => {"name": m.name, "dose": m.dose, "frequency": m.frequency})
          .toList(),
      "providers": p.doctors.map((d) => {"name": d.name, "phone": d.phone}).toList(),
      "updatedAt": p.updatedAt.toIso8601String(),
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900, // ✅ red theme
        foregroundColor: Colors.white,
        title: Text(
          "Emergency Info${p.fullName.isNotEmpty ? " – ${p.fullName}" : ""}",
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: "Edit Profile",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              ).then((_) => _load());
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                "assets/images/logo_icon.png",
                width: MediaQuery.of(context).size.width * 0.9,
                fit: BoxFit.contain,
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (p.fullName.isNotEmpty)
                ListTile(
                  title: const Text("Name"),
                  subtitle: Text(p.fullName),
                ),
              if (p.dob?.isNotEmpty == true)
                ListTile(
                  title: const Text("Date of Birth"),
                  subtitle: Text(Formatters.dob(p.dob!)),
                ),
              if (e.allergies.isNotEmpty)
                ListTile(
                  title: const Text("Allergies"),
                  subtitle: Text(e.allergies),
                ),
              if (e.conditions.isNotEmpty)
                ListTile(
                  title: const Text("Medical Conditions"),
                  subtitle: Text(e.conditions),
                ),
              if (e.contact.isNotEmpty || e.phone.isNotEmpty)
                ListTile(
                  title: const Text("Emergency Contact"),
                  subtitle: Text([
                    if (e.contact.isNotEmpty) e.contact,
                    if (e.phone.isNotEmpty) Formatters.phone(e.phone),
                  ].join(" • ")),
                ),

              const Divider(height: 32, color: Colors.redAccent), // ✅ red accent

              const Text(
                "Show this QR code to emergency personnel:",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 240,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
