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
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.loadProfile();
    setState(() {
      _p = p ?? Profile(meds: [], doctors: []);
      _loading = false;
    });
  }

  Future<void> _save() async {
    _p!.updatedAt = DateTime.now();
    await _repo.saveProfile(_p!);
    setState(() {});
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

  Future<void> _addOrEdit({
    Medication? existing,
    int? index,
    Map<String, dynamic>? prefill,
  }) async {
    final name =
        TextEditingController(text: prefill?['name'] ?? existing?.name ?? '');
    final dose =
        TextEditingController(text: prefill?['dose'] ?? existing?.dose ?? '');
    final freq = TextEditingController(
        text: prefill?['frequency'] ?? existing?.frequency ?? '');
    final pharmacy = TextEditingController(
        text: prefill?['prescriber'] ?? existing?.prescriber ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Add Medication' : 'Edit Medication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: dose, decoration: const InputDecoration(labelText: 'Dose / Strength')),
            TextField(controller: freq, decoration: const InputDecoration(labelText: 'Frequency')),
            TextField(controller: pharmacy, decoration: const InputDecoration(labelText: 'Pharmacy / Prescriber')),
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
      name: name.text.trim(),
      dose: dose.text.trim(),
      frequency: freq.text.trim(),
      prescriber: pharmacy.text.trim(),
      source: existing?.source ?? (prefill != null ? 'Scanned' : 'Manual'),
      updatedAt: DateTime.now(),
    );

    final meds = _p!.meds;

    final matchIndex = meds.indexWhere((x) =>
        x.name.toLowerCase() == m.name.toLowerCase() &&
        x.dose.toLowerCase() == m.dose.toLowerCase());

    if (existing == null && matchIndex != -1) {
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Duplicate Medication Detected"),
          content: Text("Medication '${m.name}' already exists. What do you want to do?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, "cancel"), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(context, "add"), child: const Text("Add New")),
            FilledButton(onPressed: () => Navigator.pop(context, "update"), child: const Text("Update Existing")),
          ],
        ),
      );

      if (choice == "update") {
        setState(() => meds[matchIndex] = m);
        await _save();
        return;
      } else if (choice == "add") {
        setState(() => meds.add(m));
        await _save();
        return;
      } else {
        return;
      }
    }

    setState(() {
      if (existing == null) {
        meds.add(m);
      } else {
        meds[index!] = m;
      }
    });
    await _save();
  }

  // 🔥 UPDATED MULTI-IMAGE SCAN
  Future<void> _scanLabel() async {
    try {
      final List<String> base64Images = [];
      bool keepScanning = true;

      while (keepScanning) {
        final img = await _picker.pickImage(source: ImageSource.camera);
        if (img == null) break;

        final base64Image =
            base64Encode(await File(img.path).readAsBytes());
        base64Images.add(base64Image);

        keepScanning = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Add Another Photo?"),
                content: Text(
                    "Captured ${base64Images.length} image(s).\n\nScan another side of the bottle?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Done")),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Add More")),
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
        body: jsonEncode({
          "images": base64Images, // 🔥 ARRAY SENT
        }),
      );

      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);
        final data = _normalizeParsed(parsed['data'] ?? parsed);

        _addOrEdit(prefill: data);

        final docName = data['prescribing_doctor'];
        if (docName != null && docName.toString().isNotEmpty) {
          if (!_p!.doctors.any((d) => d.name == docName)) {
            setState(() {
              _p!.doctors.add(Doctor(
                name: docName,
                specialty: "",
                clinic: "",
                phone: "",
              ));
            });
            await _save();
          }
        }
      }
    } catch (e) {
      debugPrint("Scan error: $e");
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
      body: Column(
        children: [
          ElevatedButton.icon(
            onPressed: _scanLabel,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}