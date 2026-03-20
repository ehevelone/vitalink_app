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

  // 🔥 MULTI IMAGE CARD SCAN (FRONT + BACK)
  Future<void> _scanCard() async {
    try {
      final status = await Permission.camera.request();

      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          await openAppSettings();
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Camera permission not granted")),
        );
        return;
      }

      await Future.delayed(const Duration(milliseconds: 200));

      final List<String> images = [];
      bool keepScanning = true;

      while (keepScanning) {
        final result =
            await CunningDocumentScanner.getPictures();

        if (result == null || result.isEmpty) break;

        images.addAll(result);

        keepScanning = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Scan Back of Card?"),
                content: Text(
                  "You have ${images.length} image(s).\n\nFlip the card and scan the back.",
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, false),
                    child: const Text("Done"),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, true),
                    child: const Text("Scan Back"),
                  ),
                ],
              ),
            ) ??
            false;
      }

      if (images.isEmpty) return;

      // 🔥 FRONT + BACK ASSIGNMENT
      final front = images[0];
      final back = images.length > 1 ? images[1] : null;

      _p?.orphanCards.add(
        InsuranceCard(
          frontImagePath: front,
          backImagePath: back,
          carrier: "",
          policy: "",
        ),
      );

      await _save();
      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Card saved (front + back)")),
      );
    } catch (e, stack) {
      print("SCAN ERROR: $e");
      print(stack);

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
                          subtitle: Text(card.policy),
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