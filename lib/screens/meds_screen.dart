// lib/screens/meds_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class MedsScreen extends StatefulWidget {
  const MedsScreen({super.key});

  @override
  State<MedsScreen> createState() => _MedsScreenState();
}

class _MedsScreenState extends State<MedsScreen> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;
  bool _scanning = false;
  final ImagePicker _picker = ImagePicker();

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
      _p = p ?? Profile(meds: [], doctors: []);
      _loading = false;
    });
  }

  Future<void> _save() async {
    _p!.updatedAt = DateTime.now();
    await _repo.saveProfile(_p!);
    if (mounted) setState(() {});
  }

  // ----------------------------
  // NORMALIZATION HELPERS
  // ----------------------------

  String _normalizeMed(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'hcl'), '')
        .replaceAll(RegExp(r'hydrochloride'), '')
        .replaceAll(",", "")
        .replaceAll("-", " ")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();
  }

  String _normalizeName(String name) {
    final cleaned = name
        .toLowerCase()
        .replaceAll(",", " ")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();

    final parts = cleaned.split(" ")..removeWhere((p) => p.isEmpty);
    parts.sort();
    return parts.join(" ");
  }

  String _toLastFirstFormat(String name) {
    final cleaned = name
        .replaceAll(",", " ")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();

    final parts = cleaned.split(" ")..removeWhere((p) => p.isEmpty);
    if (parts.length < 2) return cleaned;

    final last = parts.last;
    final firstMiddle = parts.sublist(0, parts.length - 1).join(" ");
    return "$last, $firstMiddle";
  }

  bool _doctorExistsByNormalizedName(String docName) {
    final target = _normalizeName(docName);
    return _p!.doctors.any((d) => _normalizeName(d.name) == target);
  }

  Map<String, dynamic> _normalizeParsed(dynamic parsed) {
    if (parsed == null) return {};
    if (parsed is Map<String, dynamic>) {
      if (parsed.containsKey("name") || parsed.containsKey("dose")) {
        return parsed;
      }
      if (parsed.containsKey("rawText")) {
        final raw = parsed["rawText"]
            .toString()
            .replaceAll("```json", "")
            .replaceAll("```", "")
            .trim();
        try {
          return jsonDecode(raw);
        } catch (_) {
          return {};
        }
      }
    }
    return {};
  }

  String _buildPharmacyDisplay(Map<String, dynamic> data) {
    final pharm = (data['pharmacy'] ?? "").toString().trim();
    final pharmPhone = (data['pharmacy_phone'] ?? "").toString().trim();

    if (pharm.isEmpty && pharmPhone.isEmpty) return "";

    if (pharm.isNotEmpty && pharmPhone.isNotEmpty) {
      return "$pharm\n$pharmPhone";
    }

    return pharm.isNotEmpty ? pharm : pharmPhone;
  }

  // ----------------------------
  // ADD / EDIT DIALOG
  // ----------------------------

  Future<void> _addOrEdit({
    Medication? existing,
    int? index,
    Map<String, dynamic>? prefill,
  }) async {
    final nameCtrl =
        TextEditingController(text: prefill?['name'] ?? existing?.name ?? '');
    final doseCtrl =
        TextEditingController(text: prefill?['dose'] ?? existing?.dose ?? '');
    final freqCtrl = TextEditingController(
        text: prefill?['frequency'] ?? existing?.frequency ?? '');
    final pharmacyCtrl = TextEditingController(
        text: prefill?['prescriber'] ?? existing?.prescriber ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Add Medication' : 'Edit Medication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: doseCtrl, decoration: const InputDecoration(labelText: 'Dose / Strength')),
            TextField(controller: freqCtrl, decoration: const InputDecoration(labelText: 'Frequency')),
            TextField(
              controller: pharmacyCtrl,
              decoration: const InputDecoration(labelText: 'Pharmacy (and phone)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok != true) return;

    final m = Medication(
      name: nameCtrl.text.trim(),
      dose: doseCtrl.text.trim(),
      frequency: freqCtrl.text.trim(),
      prescriber: pharmacyCtrl.text.trim(),
      source: existing?.source ?? (prefill != null ? 'Scanned' : 'Manual'),
      updatedAt: DateTime.now(),
    );

    setState(() {
      if (existing == null) {
        _p!.meds.add(m);
      } else {
        _p!.meds[index!] = m;
      }
    });

    await _save();
  }

  // ----------------------------
  // SCAN LABEL
  // ----------------------------

  Future<void> _scanLabel() async {
    if (_scanning) return;
    setState(() => _scanning = true);

    try {
      final List<String> base64Images = [];
      bool keepScanning = true;

      while (keepScanning) {
        final img = await _picker.pickImage(source: ImageSource.camera);
        if (img == null) break;

        final base64Image = base64Encode(await File(img.path).readAsBytes());
        base64Images.add(base64Image);

        keepScanning = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text(
                  "Did we get all sides of the bottle?",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                content: Text(
                  "You have taken ${base64Images.length} photo(s).\n\nIf the label wraps around the bottle, take another photo.",
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Yes, Continue")),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Take Another Photo")),
                ],
              ),
            ) ??
            false;
      }

      if (base64Images.isEmpty) return;

      const url =
          "https://vitalink-app.netlify.app/.netlify/functions/parse_label";

      final resp = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"images": base64Images}),
      );

      if (resp.statusCode != 200) return;

      final parsed = jsonDecode(resp.body);
      final data = _normalizeParsed(parsed['data'] ?? parsed);

      final scannedName = (data['name'] ?? "").toString().trim();
      final scannedDose = (data['dose'] ?? "").toString().trim();
      final scannedFreq = (data['frequency'] ?? "").toString().trim();
      final pharmacyDisplay = _buildPharmacyDisplay(data);

      if (scannedName.isEmpty) return;

      final normalizedScannedName = _normalizeMed(scannedName);

      final existingIndex = _p!.meds.indexWhere(
        (m) => _normalizeMed(m.name) == normalizedScannedName,
      );

      if (existingIndex != -1) {
        final existing = _p!.meds[existingIndex];

        final choice = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text(
              "This Medication Is Already Saved",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("You already have:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text("${existing.name} ${existing.dose}".trim()),
                const SizedBox(height: 12),
                const Text("The bottle says:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text("$scannedName $scannedDose".trim()),
                const SizedBox(height: 16),
                const Text("What would you like to do?",
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, "cancel"),
                  child: const Text("Cancel")),
              TextButton(
                  onPressed: () => Navigator.pop(context, "add"),
                  child: const Text("Keep Both")),
              FilledButton(
                  onPressed: () => Navigator.pop(context, "replace"),
                  child: const Text("Update This Medication")),
            ],
          ),
        );

        if (choice == "replace") {
          setState(() {
            _p!.meds[existingIndex] = Medication(
              name: scannedName,
              dose: scannedDose,
              frequency: scannedFreq,
              prescriber: pharmacyDisplay,
              source: "Scanned",
              updatedAt: DateTime.now(),
            );
          });
          await _save();
        } else if (choice == "add") {
          setState(() {
            _p!.meds.add(Medication(
              name: scannedName,
              dose: scannedDose,
              frequency: scannedFreq,
              prescriber: pharmacyDisplay,
              source: "Scanned",
              updatedAt: DateTime.now(),
            ));
          });
          await _save();
        }
      } else {
        await _addOrEdit(prefill: {
          "name": scannedName,
          "dose": scannedDose,
          "frequency": scannedFreq,
          "prescriber": pharmacyDisplay,
        });
      }

      final docName = (data['prescribing_doctor'] ?? "").toString().trim();
      if (docName.isNotEmpty) {
        final normalizedParsed = _normalizeName(docName);
        final normalizedProfile = _normalizeName(_p!.fullName);

        if (normalizedParsed != normalizedProfile &&
            !_doctorExistsByNormalizedName(docName)) {
          final formatted = _toLastFirstFormat(docName);

          setState(() {
            _p!.doctors.add(Doctor(
              name: formatted,
              specialty: "",
              clinic: "",
              phone: "",
            ));
          });

          await _save();
        }
      }
    } catch (e) {
      debugPrint("Scan error: $e");
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove medication?"),
        content: Text(_p!.meds[i].name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text("Remove")),
        ],
      ),
    );

    if (ok == true) {
      setState(() => _p!.meds.removeAt(i));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final meds = _p!.meds;

    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      body: Stack(
        children: [
          Column(
            children: [
              ElevatedButton.icon(
                onPressed: _scanning ? null : _scanLabel,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Scan Medication Label'),
              ),
              Expanded(
                child: meds.isEmpty
                    ? const Center(child: Text('No medications yet. Tap + to add.'))
                    : ListView.builder(
                        itemCount: meds.length,
                        itemBuilder: (_, i) {
                          final m = meds[i];
                          return ListTile(
                            title: Text(m.name),
                            subtitle: Text("${m.dose} ${m.frequency}".trim()),
                            onTap: () => _addOrEdit(existing: m, index: i),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(i),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          if (_scanning)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "Reading your medication label...",
                      style: TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}