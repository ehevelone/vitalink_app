import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import 'insurance_card_detail.dart';

class InsuranceCardsMenuScreen extends StatefulWidget {
  const InsuranceCardsMenuScreen({super.key});

  @override
  State<InsuranceCardsMenuScreen> createState() =>
      _InsuranceCardsMenuScreenState();
}

class _InsuranceCardsMenuScreenState extends State<InsuranceCardsMenuScreen> {
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
    debugPrint("👉 Loading profile in InsuranceCardsMenuScreen...");
    final p = await _repo.loadProfile();
    if (!mounted) return;
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

  /// ✅ Scan insurance card (front + optional back)
  Future<void> _scanCard() async {
    DocumentScanner? scanner;
    try {
      final options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: 1,
        isGalleryImport: true,
      );

      scanner = DocumentScanner(options: options);

      // ---------- FRONT ----------
      final result = await scanner.scanDocument();
      final images = result?.images;

      if (images == null || images.isEmpty) return;

      final frontPath = images.first;

      // ---------- BACK (optional) ----------
      final wantsBack = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Scan Back of Card?"),
          content: const Text("Would you like to capture the back side too?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Skip"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Yes, Scan Back"),
            ),
          ],
        ),
      );

      String? backPath;

      if (wantsBack == true) {
        final backScanner = DocumentScanner(options: options);
        try {
          final backResult = await backScanner.scanDocument();
          final backImages = backResult?.images;

          if (backImages != null && backImages.isNotEmpty) {
            backPath = backImages.first;
          }
        } finally {
          await backScanner.close();
        }
      }

      setState(() {
        _p!.orphanCards.add(
          InsuranceCard(
            carrier: '',
            policy: '',
            memberId: '',
            policyType: '',
            frontImagePath: frontPath,
            backImagePath: backPath,
            source: 'Scanned',
          ),
        );
      });

      await _save();
    } catch (e) {
      debugPrint("❌ Exception while scanning card: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Scan failed: $e")),
        );
      }
    } finally {
      try {
        await scanner?.close();
      } catch (_) {}
    }
  }

  void _deleteCard(InsuranceCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete card?"),
        content: const Text("This card will be permanently removed."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete")),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _p!.orphanCards.removeWhere((c) => c.id == card.id);
        for (var ins in _p!.insurances) {
          ins.cards.removeWhere((c) => c.id == card.id);
        }
      });
      await _save();
    }
  }

  Widget _cardRow(InsuranceCard card) {
    final frontFile = File(card.frontImagePath);
    final backFile =
        card.backImagePath != null ? File(card.backImagePath!) : null;

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          frontFile.existsSync()
              ? Image.file(frontFile, width: 80, height: 60, fit: BoxFit.cover)
              : const Icon(Icons.broken_image, size: 60),
          const SizedBox(width: 8),
          if (backFile != null && backFile.existsSync())
            Image.file(backFile, width: 80, height: 60, fit: BoxFit.cover),
        ],
      ),
      title: Text(card.carrier.isNotEmpty ? card.carrier : "Insurance Card"),
      subtitle: Text(card.policy.isNotEmpty ? card.policy : ""),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.black),
        onPressed: () => _deleteCard(card),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InsuranceCardDetail(
              card: card,
              onDelete: () => _deleteCard(card),
              startOnBack: false,
            ),
          ),
        );
      },
    );
  }

  Map<String, List<InsuranceCard>> _categorizeCards(List<InsuranceCard> cards) {
    final Map<String, List<InsuranceCard>> buckets = {
      "Primary": [],
      "Supplement": [],
      "PDP": [],
      "MAPD/MA": [],
      "VA/TriCare": [],
      "Ancillary": [],
    };

    for (var card in cards) {
      final carrier = card.carrier.toLowerCase();
      final policy = card.policy.toLowerCase();
      final type = card.policyType.toLowerCase();

      if (carrier.contains("medicare") &&
          (policy.contains("part a") || policy.contains("part b"))) {
        buckets["Primary"]!.add(card);
      } else if (policy.contains("plan a") ||
          policy.contains("plan b") ||
          policy.contains("plan c") ||
          policy.contains("plan d") ||
          policy.contains("plan f") ||
          policy.contains("plan g") ||
          policy.contains("plan n")) {
        buckets["Supplement"]!.add(card);
      } else if (carrier.contains("pdp") || policy.contains("part d")) {
        buckets["PDP"]!.add(card);
      } else if (carrier.contains("mapd") ||
          policy.contains("mapd") ||
          policy.contains("advantage") ||
          type.contains("ma")) {
        buckets["MAPD/MA"]!.add(card);
      } else if (carrier.contains("va") || carrier.contains("tricare")) {
        buckets["VA/TriCare"]!.add(card);
      } else {
        buckets["Ancillary"]!.add(card);
      }
    }

    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final allCards = [
      ..._p!.orphanCards,
      for (var ins in _p!.insurances) ...ins.cards,
    ];

    final categorized = _categorizeCards(allCards);

    return Scaffold(
      appBar: AppBar(title: const Text("Insurance Cards")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _scanCard,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Scan Insurance Card'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: categorized.entries
                  .where((entry) => entry.value.isNotEmpty)
                  .map((entry) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Column(
                            children: entry.value
                                .map((card) => _cardRow(card))
                                .toList(),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
