import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import 'insurance_card_detail.dart';

class IOSCardScanScreen extends StatefulWidget {
  const IOSCardScanScreen({super.key});

  @override
  State<IOSCardScanScreen> createState() =>
      _IOSCardScanScreenState();
}

class _IOSCardScanScreenState
    extends State<IOSCardScanScreen> {
  late final DataRepository _repo;

  Profile? _p;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.loadProfile();
      if (!mounted) return;

      setState(() {
        _p = p;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _save() async {
    if (_p == null) return;
    _p!.updatedAt = DateTime.now();
    await _repo.saveProfile(_p!);
  }

  // 🔥 Permission-safe scanner
  Future<void> _scanCard() async {
    // Check permission first
    var status = await Permission.camera.status;

    if (!status.isGranted) {
      final result = await Permission.camera.request();

      if (!result.isGranted) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Camera permission required"),
          ),
        );

        await openAppSettings();
        return;
      }
    }

    try {
      final images =
          await CunningDocumentScanner.getPictures();

      if (images == null || images.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Scan cancelled")),
        );
        return;
      }

      final imagePath = images.first;

      _p?.orphanCards.add(
        InsuranceCard(
          frontImagePath: imagePath,
          carrier: "",
          policy: "",
        ),
      );

      await _save();
      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Card added")),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Scanner error: $e")),
      );
    }
  }

  void _deleteCard(InsuranceCard card) async {
    _p?.orphanCards.remove(card);

    for (var ins in _p?.insurances ?? []) {
      ins.cards.remove(card);
    }

    await _save();
    await _load();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Card deleted")),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error || _p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Insurance Cards")),
        body: const Center(
          child: Text("Unable to load insurance cards."),
        ),
      );
    }

    final allCards = [
      ..._p?.orphanCards ?? [],
      for (var ins in _p?.insurances ?? []) ...ins.cards,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Insurance Cards")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: _scanCard,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text("Scan Insurance Card"),
            ),
          ),
          Expanded(
            child: allCards.isEmpty
                ? const Center(
                    child: Text("No insurance cards found"),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: allCards.length,
                    itemBuilder: (context, index) {
                      final card = allCards[index];
                      final file = File(card.frontImagePath);

                      return Card(
                        child: ListTile(
                          leading: file.existsSync()
                              ? Image.file(
                                  file,
                                  width: 70,
                                  height: 50,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(Icons.broken_image),
                          title: Text(
                            card.carrier.isNotEmpty
                                ? card.carrier
                                : "Insurance Card",
                          ),
                          subtitle: Text(card.policy ?? ''),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    InsuranceCardDetail(
                                        card: card),
                              ),
                            );
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.red),
                            onPressed: () =>
                                _deleteCard(card),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}