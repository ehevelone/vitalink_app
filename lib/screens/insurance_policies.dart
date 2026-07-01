import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import 'insurance_policy_view.dart';
import 'insurance_policy_form.dart';
import 'vitalink_camera_capture_screen.dart';

class InsurancePoliciesScreen extends StatefulWidget {
  const InsurancePoliciesScreen({super.key});

  @override
  State<InsurancePoliciesScreen> createState() =>
      _InsurancePoliciesScreenState();
}

class _InsurancePoliciesScreenState extends State<InsurancePoliciesScreen> {
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

  Future<void> _save() async {
    if (_p == null) return;
    _p!.updatedAt = DateTime.now();
    await _repo.saveProfile(_p!);
    setState(() {});
  }

  Map<String, dynamic> _normalizeParsed(dynamic parsed) {
    if (parsed == null) return {};
    if (parsed is Map<String, dynamic>) {
      if (parsed.containsKey("carrier") || parsed.containsKey("policy")) {
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

  Future<void> _scanPolicy() async {
    try {
      if (_p == null) return;

      final imagePaths = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (_) => const VitalinkCameraCaptureScreen(
            title: 'Scan Insurance Policy',
            reviewTitle: 'Can you read the policy page?',
            instructions:
                'Hold the phone steady and fill the screen with the policy page.',
            addAnotherLabel: 'Add Another Page',
            maxPhotos: 6,
          ),
        ),
      );

      final List<String> base64Images = [];
      for (final path in imagePaths ?? <String>[]) {
        final bytes = await File(path).readAsBytes();
        base64Images.add(base64Encode(bytes));
      }

      if (base64Images.isEmpty) return;

      const url =
          "https://vitalink-app.netlify.app/.netlify/functions/parse_insurance";

      final store = SecureStore();
      final userId = await store.getString("userId");
      final sessionToken = await store.getString("userSessionToken");

      if (userId == null ||
          userId.isEmpty ||
          sessionToken == null ||
          sessionToken.isEmpty) {
        throw Exception("Please log in again before scanning.");
      }

      final resp = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "images": base64Images,
          "userId": userId,
          "sessionToken": sessionToken,
        }),
      );

      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);
        final normalized = _normalizeParsed(parsed['data'] ?? parsed);

        final newPolicy = Insurance(
          carrier: (normalized['carrier'] ?? '').trim(),
          policy: (normalized['policy'] ?? '').trim(),
          memberId: (normalized['memberId'] ?? '').trim(),
          group: (normalized['group'] ?? '').trim(),
          policyType: (normalized['planType'] ?? '').trim(),

          // 🔥 NEW FIELDS
          insuredName: (normalized['insuredName'] ?? '').trim(),
          beneficiary: (normalized['beneficiary'] ?? '').trim(),

          // 🔥 BENEFITS FIX
          benefits: (normalized['benefits'] as List<dynamic>? ?? [])
              .map((b) => {
                    'name': b['name']?.toString() ?? '',
                    'value': b['value']?.toString() ?? '',
                  })
              .toList(),

          cards: [],
        );

        final policies = _p!.insurances;

        final matchIndex = policies.indexWhere((i) =>
            i.carrier.toLowerCase() == newPolicy.carrier.toLowerCase() &&
            i.policy.toLowerCase() == newPolicy.policy.toLowerCase());

        if (matchIndex != -1) {
          if (!mounted) return;
          final choice = await showDialog<String>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Duplicate Detected"),
              content: Text(
                  "Policy '${newPolicy.carrier} – ${newPolicy.policy}' already exists."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, "cancel"),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, "add"),
                  child: const Text("Add New"),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, "update"),
                  child: const Text("Update Existing"),
                ),
              ],
            ),
          );

          if (choice == "update") {
            setState(() => policies[matchIndex] = newPolicy);
            await _save();
            return;
          } else if (choice == "add") {
            setState(() => policies.add(newPolicy));
            await _save();
            return;
          } else {
            return;
          }
        }

        if (!mounted) return;
        final updated = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InsurancePolicyForm(
              policy: newPolicy,
              allPolicies: policies,
            ),
          ),
        );

        if (updated != null) {
          setState(() => policies.add(updated));
          await _save();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Policy scan failed: $e")),
      );
    }
  }

  Future<void> _addPolicy() async {
    if (_p == null) return;

    final newPolicy = Insurance();
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InsurancePolicyForm(
          policy: newPolicy,
          allPolicies: _p!.insurances,
        ),
      ),
    );

    if (updated != null) {
      setState(() => _p!.insurances.add(updated));
      await _save();
    }
  }

  Future<void> _delete(int i) async {
    if (_p == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove policy?"),
        content: Text(_p!.insurances[i].carrier),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() => _p!.insurances.removeAt(i));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _p == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final insurances = _p!.insurances;

    return Scaffold(
      appBar: AppBar(title: const Text("Insurance Policies")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(
              onPressed: _scanPolicy,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.camera_alt),
              label: const Text(
                "Scan Insurance Policy",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: insurances.isEmpty
                ? const Center(
                    child: Text("No insurance policies yet. Tap + to add."),
                  )
                : ListView.builder(
                    itemCount: insurances.length,
                    itemBuilder: (_, i) {
                      final ins = insurances[i];
                      return ListTile(
                        title: Text(
                          ins.carrier.isNotEmpty
                              ? ins.carrier
                              : "Unnamed Policy",
                        ),
                        subtitle: Text(
                          "Policy #: ${ins.policy.isNotEmpty ? ins.policy : 'N/A'}",
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InsurancePolicyView(index: i),
                            ),
                          ).then((_) => _load());
                        },
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
        onPressed: _addPolicy,
        child: const Icon(Icons.add),
      ),
    );
  }
}
