import 'dart:io';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/persistent_file_store.dart';
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
  static const double _maxPickedImageSize = 2048;
  static const int _pickedImageQuality = 88;

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

    await _autoAttachCards(); // 🔥 ADDED
  }

  Future<void> _save() async {
    if (_p != null) {
      _p!.updatedAt = DateTime.now();
      await _repo.saveProfile(_p!);
    }
  }

  // 🔥 AUTO ATTACH CARDS (NEW)
  Future<void> _autoAttachCards() async {
    if (_p == null) return;

    final policy = _p!.insurances[widget.index];
    final orphanCards = _p!.orphanCards;

    if (orphanCards.isEmpty) return;

    bool updated = false;

    for (final card in List<InsuranceCard>.from(orphanCards)) {
      final policyMatch = card.policy.trim().toLowerCase() ==
          policy.policy.trim().toLowerCase();

      if (policyMatch && card.policy.isNotEmpty) {
        policy.cards.add(card);
        orphanCards.remove(card);
        updated = true;
      }
    }

    if (updated) {
      await _save();

      if (mounted) {
        setState(() {});
        _showSnack(AppStrings.of(context).cardLinkedToPolicy);
      }
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
        title: Text(AppStrings.of(context).deletePolicyQuestion),
        content: Text(AppStrings.of(context).deletePolicyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).delete),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _p!.insurances.removeAt(widget.index);
      });
      await _save();
      if (!mounted) return;
      _showSnack(AppStrings.of(context).policyDeleted);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _addDecPageFromGallery() async {
    if (_p == null) return;
    final img = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxPickedImageSize,
      maxHeight: _maxPickedImageSize,
      imageQuality: _pickedImageQuality,
    );
    if (img == null) return;
    final permanentPath = await PersistentFileStore.saveBytes(
      await img.readAsBytes(),
      folder: 'declaration_pages',
    );

    setState(() {
      _p!.insurances[widget.index].decPagePaths.add(permanentPath);
    });

    await _save();

    if (!mounted) return;
    _showSnack(AppStrings.of(context).declarationPageAdded);
  }

  Future<void> _addDecPageFromCamera() async {
    if (_p == null) return;
    final img = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxPickedImageSize,
      maxHeight: _maxPickedImageSize,
      imageQuality: _pickedImageQuality,
    );
    if (img == null) return;
    final permanentPath = await PersistentFileStore.saveBytes(
      await img.readAsBytes(),
      folder: 'declaration_pages',
    );

    setState(() {
      _p!.insurances[widget.index].decPagePaths.add(permanentPath);
    });

    await _save();

    if (!mounted) return;
    _showSnack(AppStrings.of(context).declarationPageCaptured);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _p == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ins = _p!.insurances[widget.index];
    final profileName = (_p!.fullName.isNotEmpty ? " – ${_p!.fullName}" : "");

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (ins.carrier.isNotEmpty
                  ? ins.carrier
                  : AppStrings.of(context).insurancePolicy) +
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
                if (!context.mounted) return;
                _showSnack(AppStrings.of(context).policyUpdated);
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
          if (ins.cards.isNotEmpty && ins.cards.first.frontImagePath.isNotEmpty)
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
                              cacheWidth: 2048,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: Image.file(
                    File(ins.cards.first.frontImagePath),
                    height: 180,
                    cacheHeight: 360,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),

          // BASIC INFO
          ListTile(
            title: Text(AppStrings.of(context).carrier),
            subtitle: Text(ins.carrier.isNotEmpty
                ? ins.carrier
                : AppStrings.of(context).notAvailable),
          ),
          ListTile(
            title: Text(AppStrings.of(context).policyNumber),
            subtitle: Text(ins.policy.isNotEmpty
                ? ins.policy
                : AppStrings.of(context).notAvailable),
          ),
          ListTile(
            title: Text(AppStrings.of(context).memberId),
            subtitle: Text(ins.memberId.isNotEmpty
                ? ins.memberId
                : AppStrings.of(context).notAvailable),
          ),
          ListTile(
            title: Text(AppStrings.of(context).policyType),
            subtitle: Text(ins.policyType.isNotEmpty
                ? ins.policyType
                : AppStrings.of(context).notAvailable),
          ),

          // 🔥 NEW FIELDS
          ListTile(
            title: Text(AppStrings.of(context).insured),
            subtitle: Text(ins.insuredName.isNotEmpty
                ? ins.insuredName
                : AppStrings.of(context).notAvailable),
          ),
          ListTile(
            title: Text(AppStrings.of(context).beneficiary),
            subtitle: Text(ins.beneficiary.isNotEmpty
                ? ins.beneficiary
                : AppStrings.of(context).notAvailable),
          ),

          const Divider(),

          // 🔥 BENEFITS SECTION
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              AppStrings.of(context).benefits,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            Text(AppStrings.of(context).noBenefitsExtracted),

          const Divider(),

          // CARDS BUTTON
          ElevatedButton.icon(
            icon: const Icon(Icons.credit_card),
            label: Text(AppStrings.of(context).viewCards),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InsuranceCardsScreen(index: widget.index),
                ),
              );
            },
          ),

          const Divider(),

          // DECLARATION PAGES
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              AppStrings.of(context).declarationPages,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: Text(AppStrings.of(context).upload),
                onPressed: _addDecPageFromGallery,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: Text(AppStrings.of(context).camera),
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
                      title: Text(AppStrings.of(context)
                          .pageValue(path.split('/').last)),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DeclarationPageViewer(path: path),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            )
          else
            Text(AppStrings.of(context).noDeclarationPagesUploaded),
        ],
      ),
    );
  }
}
