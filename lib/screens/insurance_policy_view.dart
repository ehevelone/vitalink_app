import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import 'insurance_policy_form.dart';
import 'declaration_page_viewer.dart';
import 'insurance_cards.dart';

class InsurancePolicyView extends StatefulWidget {
  final int index;

  const InsurancePolicyView({super.key, required this.index});

  @override
  State<InsurancePolicyView> createState() => _InsurancePolicyViewState();
}

class _InsurancePolicyViewState extends State<InsurancePolicyView> {
  late final DataRepository _repo;
  final ImagePicker _picker = ImagePicker();
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

  Future<void> _save() async {
    if (_p != null) {
      _p!.updatedAt = DateTime.now();
      await _repo.saveProfile(_p!);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _deletePolicy() async {
    if (_p == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Policy?"),
        content: const Text("This will permanently remove this policy."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _p!.insurances.removeAt(widget.index);
      });
      await _save();
      _showSnack("Policy deleted");
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _addDecPageFromGallery() async {
    if (_p == null) return;
    final img = await _picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;

    setState(() {
      _p!.insurances[widget.index].decPagePaths.add(img.path);
    });

    await _save();
    _showSnack("Declaration page added");
  }

  Future<void> _addDecPageFromCamera() async {
    if (_p == null) return;
    final img = await _picker.pickImage(source: ImageSource.camera);
    if (img == null) return;

    setState(() {
      _p!.insurances[widget.index].decPagePaths.add(img.path);
    });

    await _save();
    _showSnack("Declaration page captured");
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _p == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ins = _p!.insurances[widget.index];
    final profileName =
        (_p!.fullName.isNotEmpty ? " – ${_p!.fullName}" : "");

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (ins.carrier.isNotEmpty ? ins.carrier : "Insurance Policy") +
              profileName,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final updated = await Navigator.push<Insurance>(
                context,
                MaterialPageRoute(
                  builder: (_) => InsurancePolicyForm(
                    policy: ins,
                    allPolicies: _p!.insurances,
                  ),
                ),
              );

              if (updated != null) {
                setState(() {
                  _p!.insurances[widget.index] = updated;
                });
                await _save();
                _showSnack("Policy updated");
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deletePolicy,
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // CARD IMAGE
          if (ins.cards.isNotEmpty &&
              ins.cards.first.frontImagePath.isNotEmpty)
            Column(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(),
                          body: Center(
                            child: Image.file(
                              File(ins.cards.first.frontImagePath),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: Image.file(
                    File(ins.cards.first.frontImagePath),
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),

          // BASIC INFO
          ListTile(
            title: const Text("Carrier"),
            subtitle: Text(ins.carrier.isNotEmpty ? ins.carrier : "N/A"),
          ),
          ListTile(
            title: const Text("Policy #"),
            subtitle: Text(ins.policy.isNotEmpty ? ins.policy : "N/A"),
          ),
          ListTile(
            title: const Text("Member ID"),
            subtitle: Text(ins.memberId.isNotEmpty ? ins.memberId : "N/A"),
          ),
          ListTile(
            title: const Text("Policy Type"),
            subtitle: Text(ins.policyType.isNotEmpty ? ins.policyType : "N/A"),
          ),

          // 🔥 NEW FIELDS
          ListTile(
            title: const Text("Insured"),
            subtitle: Text(
                ins.insuredName.isNotEmpty ? ins.insuredName : "N/A"),
          ),
          ListTile(
            title: const Text("Beneficiary"),
            subtitle: Text(
                ins.beneficiary.isNotEmpty ? ins.beneficiary : "N/A"),
          ),

          const Divider(),

          // 🔥 BENEFITS SECTION
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "Benefits",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

          if (ins.benefits.isNotEmpty)
            Column(
              children: ins.benefits.map((b) {
                final name = b['name'] ?? '';
                final value = b['value'] ?? '';
                return ListTile(
                  title: Text(name),
                  subtitle: Text(value),
                );
              }).toList(),
            )
          else
            const Text("No benefits extracted."),

          const Divider(),

          // CARDS BUTTON
          ElevatedButton.icon(
            icon: const Icon(Icons.credit_card),
            label: const Text("View Cards"),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      InsuranceCardsScreen(index: widget.index),
                ),
              );
            },
          ),

          const Divider(),

          // DECLARATION PAGES
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "Declaration Pages",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text("Upload"),
                onPressed: _addDecPageFromGallery,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text("Camera"),
                onPressed: _addDecPageFromCamera,
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (ins.decPagePaths.isNotEmpty)
            Column(
              children: [
                for (final path in ins.decPagePaths)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.picture_as_pdf),
                      title: Text("Page: ${path.split('/').last}"),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DeclarationPageViewer(path: path),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            )
          else
            const Text("No declaration pages uploaded."),
        ],
      ),
    );
  }
}