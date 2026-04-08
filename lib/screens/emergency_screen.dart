import 'dart:convert';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
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

  Future<void> _syncToBackend(Profile p) async {
    final e = p.emergency;

    final data = {
      "name": p.fullName,
      "dob": p.dob ?? "",
      "allergies": e.allergies,
      "conditions": e.conditions,
      "implants": e.implants,
      "procedures": e.procedures,
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

    try {
      final res = await ApiService.saveEmergencyProfile(
        profileId: p.id,
        data: data,
      );

      if (res["success"] != true) {
        debugPrint("⚠️ Save failed: ${res["error"]}");
      }

      // 🔥 FIX: Persist token locally
      if (res["qr_token"] != null && res["qr_token"].toString().isNotEmpty) {
        p.qrToken = res["qr_token"];
        await _repo.saveProfile(p); // ✅ CRITICAL FIX
      }

    } catch (e) {
      debugPrint("Save emergency profile failed: $e");
    }
  }

  Future<void> _showQr() async {
    final p = _p;
    if (p == null) return;

    if (p.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile not ready. Please try again.")),
      );
      return;
    }

    await _syncToBackend(p);

    final qrUrl = (p.qrToken != null && p.qrToken!.isNotEmpty)
        ? "https://myvitalink.app/emergency.html?token=${p.qrToken}"
        : "https://myvitalink.app/emergency.html?id=${p.id}";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrScreen(
          data: qrUrl,
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
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).padding.bottom + 120,
            ),
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
                title: const Text("Implanted Devices"),
                subtitle: Text(e.implants.isNotEmpty ? e.implants : "N/A"),
              ),

              ListTile(
                title: const Text("Major Procedures"),
                subtitle: Text(e.procedures.isNotEmpty ? e.procedures : "N/A"),
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

              if (p.meds.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Medications",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...p.meds.map((m) => ListTile(
                          dense: true,
                          title: Text(m.name.isNotEmpty ? m.name : "Unknown"),
                          subtitle: Text(
                            [
                              if (m.dose.isNotEmpty) m.dose,
                              if (m.frequency.isNotEmpty) m.frequency,
                            ].join(" • "),
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],
                ),

              if (p.doctors.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Doctors",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...p.doctors.map((d) => ListTile(
                          dense: true,
                          title: Text(d.name.isNotEmpty ? d.name : "Unknown"),
                          subtitle: Text(
                            d.phone.isNotEmpty
                                ? Formatters.phone(d.phone)
                                : "No phone",
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],
                ),

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

          Positioned(
            bottom: 10,
            left: 16,
            right: 16,
            child: Text(
              "VitaLink provides personal health information for emergency reference only. "
              "It does not replace professional medical care. Always rely on medical professionals.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red.shade700,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
          ).then((_) async {
            await _load();
            if (_p != null && _p!.id.isNotEmpty) {
              await _syncToBackend(_p!);
            }
          });
        },
        child: const Icon(Icons.edit),
      ),
    );
  }
}