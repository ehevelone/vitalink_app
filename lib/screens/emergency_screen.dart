import 'dart:convert';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import 'qr_screen.dart';
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

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
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
      _p = p ?? Profile();
      _loading = false;
    });
  }

  void _showQr() {
    final p = _p;
    if (p == null) return;
    final e = p.emergency;

    final data = {
      "name": p.fullName,
      "dob": p.dob ?? "",
      "allergies": e.allergies,
      "conditions": e.conditions,
      "bloodType": e.bloodType,
      "organDonor": e.organDonor,
      "emergencyContactName": e.contact,
      "emergencyContactPhone": e.phone,
      "meds": p.meds.map((m) => {
            "name": m.name,
            "dose": m.dose,
            "frequency": m.frequency,
          }).toList(),
      "providers": p.doctors.map((d) => {
            "name": d.name,
            "phone": d.phone,
          }).toList(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrScreen(
          data: jsonEncode(data),
          title: "Emergency Info",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _p == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final p = _p!;
    final e = p.emergency;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        title: Text(
          p.fullName.isNotEmpty ? p.fullName : "Emergency Info",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Image.asset("assets/images/app_icon.png", height: 32),
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
              if (p.dob?.isNotEmpty == true)
                ListTile(
                  title: const Text("Date of Birth"),
                  subtitle: Text(Formatters.dob(p.dob!)),
                ),
              ListTile(
                title: const Text("Emergency Contact"),
                subtitle: Text(e.contact.isNotEmpty ? e.contact : "N/A"),
              ),
              ListTile(
                title: const Text("Phone"),
                subtitle: Text(
                  e.phone.isNotEmpty ? Formatters.phone(e.phone) : "N/A",
                ),
              ),
              ListTile(
                title: const Text("Allergies"),
                subtitle: Text(e.allergies.isNotEmpty ? e.allergies : "N/A"),
              ),
              ListTile(
                title: const Text("Conditions"),
                subtitle: Text(e.conditions.isNotEmpty ? e.conditions : "N/A"),
              ),
              ListTile(
                title: const Text("Blood Type"),
                subtitle: Text(e.bloodType.isNotEmpty ? e.bloodType : "N/A"),
              ),
              ListTile(
                title: const Text("Organ Donor"),
                subtitle: Text(
                  e.organDonor ? "YES" : "NO",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: e.organDonor
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                    fontSize: 17,
                  ),
                ),
              ),

              const Divider(height: 32),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.qr_code),
                label: const Text("Show Emergency QR"),
                onPressed: _showQr,
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red.shade700,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
          ).then((_) => _load());
        },
        child: const Icon(Icons.edit),
      ),
    );
  }
}
