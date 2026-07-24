import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../l10n/app_strings.dart';
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
      _p = p;
      _loading = false;
    });
  }

  // 🔥 UPDATED — SAFE QR CACHE + FALLBACK
  Future<void> _showQr() async {
    final p = _p;
    if (p == null) return;

    if (p.id.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).profileNotReady)),
      );
      return;
    }

    try {
      final store = SecureStore();

      // ✅ STEP 1: LOCAL CACHE
      final savedUrl = await store.getString('qr_url');

      if (savedUrl != null && savedUrl.isNotEmpty) {
        if (!mounted) return;
        final token = savedUrl.split("token=").last;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QrScreen(
              qrToken: token,
              title: AppStrings.of(context).emergencyInfo,
            ),
          ),
        );
        return;
      }

      // 🔥 STEP 2: FALLBACK TO API (ORIGINAL LOGIC)
      final res = await ApiService.getProfiles(p.id);

      if (res["success"] != true) {
        throw Exception("API failed");
      }

      final profiles = res["profiles"] as List;

      Map<String, dynamic>? match;
      for (final x in profiles) {
        if (x["id"].toString() == p.id.toString()) {
          match = Map<String, dynamic>.from(x);
          break;
        }
      }

      match ??= profiles.isNotEmpty
          ? Map<String, dynamic>.from(profiles.first)
          : null;

      final qrToken = match?["qr_token"]?.toString();

      if (qrToken == null || qrToken.isEmpty) {
        throw Exception("No token");
      }

      // ✅ STEP 3: SAVE FOR FUTURE USE
      final qrUrl = "https://myvitalink.app/emergency.html?token=$qrToken";

      await store.setString('qr_url', qrUrl);
      if (!mounted) return;

      // ✅ STEP 4: NAVIGATE (UNCHANGED)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QrScreen(
            qrToken: qrToken,
            title: AppStrings.of(context).emergencyInfo,
          ),
        ),
      );
    } catch (e) {
      debugPrint("❌ QR LOAD FAILED: $e");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).failedToLoadQr)),
      );
    }
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
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        title: Text(
          p.fullName.isNotEmpty ? p.fullName : strings.emergencyInfo,
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
                  tileColor: Colors.transparent,
                  shape: const Border(
                    bottom: BorderSide(color: Colors.black12),
                  ),
                  title: Text(strings.dateOfBirth),
                  subtitle: Text(Formatters.dob(p.dob!)),
                ),
              if (e.effectiveContacts.isEmpty)
                ListTile(
                  tileColor: Colors.transparent,
                  shape: const Border(
                    bottom: BorderSide(color: Colors.black12),
                  ),
                  title: Text(strings.emergencyContacts),
                  subtitle: Text(strings.notAvailable),
                ),
              ...e.effectiveContacts.asMap().entries.map(
                    (entry) => ListTile(
                      tileColor: Colors.transparent,
                      shape: const Border(
                        bottom: BorderSide(color: Colors.black12),
                      ),
                      title: Text(
                        strings.emergencyContact(entry.key + 1),
                      ),
                      subtitle: Text([
                        if (entry.value.name.isNotEmpty) entry.value.name,
                        if (entry.value.phone.isNotEmpty)
                          Formatters.phone(entry.value.phone),
                      ].join(" - ")),
                    ),
                  ),
              ListTile(
                tileColor: Colors.transparent,
                shape: const Border(
                  bottom: BorderSide(color: Colors.black12),
                ),
                title: Text(strings.allergies),
                subtitle: Text(e.allergies.isNotEmpty
                    ? e.allergies
                    : strings.notAvailable),
              ),
              ListTile(
                tileColor: Colors.transparent,
                shape: const Border(
                  bottom: BorderSide(color: Colors.black12),
                ),
                title: Text(strings.conditions),
                subtitle: Text(e.conditions.isNotEmpty
                    ? e.conditions
                    : strings.notAvailable),
              ),
              ListTile(
                tileColor: Colors.transparent,
                shape: const Border(
                  bottom: BorderSide(color: Colors.black12),
                ),
                title: Text(strings.implantedDevices),
                subtitle: Text(
                    e.implants.isNotEmpty ? e.implants : strings.notAvailable),
              ),
              ListTile(
                tileColor: Colors.transparent,
                shape: const Border(
                  bottom: BorderSide(color: Colors.black12),
                ),
                title: Text(strings.majorProcedures),
                subtitle: Text(e.procedures.isNotEmpty
                    ? e.procedures
                    : strings.notAvailable),
              ),
              ListTile(
                tileColor: Colors.transparent,
                shape: const Border(
                  bottom: BorderSide(color: Colors.black12),
                ),
                title: Text(strings.bloodType),
                subtitle: Text(e.bloodType.isNotEmpty
                    ? e.bloodType
                    : strings.notAvailable),
              ),
              ListTile(
                tileColor: Colors.transparent,
                shape: const Border(
                  bottom: BorderSide(color: Colors.black12),
                ),
                title: Text(strings.organDonor),
                subtitle: Text(
                  e.organDonor ? strings.yes : strings.no,
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
                    Text(
                      strings.medications,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...p.meds.map((m) => ListTile(
                          tileColor: Colors.transparent,
                          shape: const Border(
                            bottom: BorderSide(color: Colors.black12),
                          ),
                          dense: true,
                          title: Text(
                              m.name.isNotEmpty ? m.name : strings.unknown),
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
                    Text(
                      strings.doctors,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...p.doctors.map((d) => ListTile(
                          tileColor: Colors.transparent,
                          shape: const Border(
                            bottom: BorderSide(color: Colors.black12),
                          ),
                          dense: true,
                          title: Text(
                              d.name.isNotEmpty ? d.name : strings.unknown),
                          subtitle: Text(
                            d.phone.isNotEmpty
                                ? Formatters.phone(d.phone)
                                : strings.noPhone,
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
                label: Text(strings.showEmergencyQr),
                onPressed: _showQr,
              ),
            ],
          ),
          Positioned(
            bottom: 10,
            left: 16,
            right: 16,
            child: Text(
              strings.emergencyDisclaimer,
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
          });
        },
        child: const Icon(Icons.edit),
      ),
    );
  }
}
