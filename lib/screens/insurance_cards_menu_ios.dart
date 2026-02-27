import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';

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
    try {
      _p!.updatedAt = DateTime.now();
      await _repo.saveProfile(_p!);
    } catch (_) {}
  }

  // ✅ VisionKit Scanner (cunning_document_scanner)
  Future<void> _scanCard() async {
    try {
      final images =
          await CunningDocumentScanner.getPictures();

      if (images == null || images.isEmpty) return;

      final imagePath = images.first;

      debugPrint("iOS scanned card path: $imagePath");

      _p?.orphanCards.add(
        InsuranceCard(
          frontImagePath: imagePath,
          carrier: "",
          policy: "",
        ),
      );

      await _save();
      await _load();
    } catch (e) {
      debugPrint("iOS scanner error: $e");
    }
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
        appBar:
            AppBar(title: const Text("Insurance Cards")),
        body: Center(
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off,
                  size: 60, color: Colors.grey),
              const SizedBox(height: 20),
              const Text(
                "Unable to load insurance cards.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = false;
                  });
                  _load();
                },
                child: const Text("Retry"),
              )
            ],
          ),
        ),
      );
    }

    final allCards = [
      ..._p?.orphanCards ?? [],
      for (var ins in _p?.insurances ?? [])
        ...ins.cards,
    ];

    return Scaffold(
      appBar:
          AppBar(title: const Text("Insurance Cards")),
      body: Column(
        children: [
          // ✅ SAME BUTTON AS ANDROID
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: _scanCard,
              icon: const Icon(
                  Icons.camera_alt_outlined),
              label:
                  const Text("Scan Insurance Card"),
            ),
          ),

          Expanded(
            child: allCards.isEmpty
                ? const Center(
                    child:
                        Text("No insurance cards found"))
                : ListView.builder(
                    padding:
                        const EdgeInsets.all(16),
                    itemCount: allCards.length,
                    itemBuilder:
                        (context, index) {
                      final card =
                          allCards[index];
                      final file = File(
                          card.frontImagePath);

                      return ListTile(
                        leading:
                            file.existsSync()
                                ? Image.file(
                                    file,
                                    width: 70,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(
                                    Icons
                                        .broken_image),
                        title: Text(
                          card.carrier
                                  .isNotEmpty
                              ? card.carrier
                              : "Insurance Card",
                        ),
                        subtitle:
                            Text(card.policy ?? ''),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  InsuranceCardDetail(
                                      card:
                                          card),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}