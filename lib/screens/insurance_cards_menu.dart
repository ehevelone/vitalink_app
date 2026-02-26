import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

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

class _InsuranceCardsMenuScreenState
    extends State<InsuranceCardsMenuScreen> {
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

  Future<void> _scanCard() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    try {
      String? imagePath;

      if (defaultTargetPlatform == TargetPlatform.android) {
        // Android → MLKit
        final scanner = DocumentScanner(
          options: DocumentScannerOptions(
            mode: ScannerMode.full,
            pageLimit: 1,
          ),
        );

        final result = await scanner.scanDocument();
        if (result == null ||
            result.images == null ||
            result.images!.isEmpty) return;

        imagePath = result.images!.first;

      } else if (defaultTargetPlatform == TargetPlatform.iOS) {

        // iPad detection
        final isTablet =
            MediaQuery.of(context).size.shortestSide >= 600;

        if (isTablet) {
          // iPad → fallback to camera
          final picker = ImagePicker();
          final file =
              await picker.pickImage(source: ImageSource.camera);
          if (file == null) return;
          imagePath = file.path;
        } else {
          // iPhone → Apple document scanner
          final images =
              await CunningDocumentScanner.getPictures();
          if (images == null || images.isEmpty) return;
          imagePath = images.first;
        }
      }

      if (imagePath == null) return;

      setState(() {
        _p!.orphanCards.add(
          InsuranceCard(
            frontImagePath: imagePath!,
            carrier: "",
            policy: "",
          ),
        );
      });

      await _save();

    } catch (e) {
      debugPrint("Scanner error: $e");
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
      return const Scaffold(
        body: Center(child: Text("Unable to load insurance cards")),
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
                ? const Center(child: Text("No insurance cards found"))
                : ListView.builder(
                    itemCount: allCards.length,
                    itemBuilder: (context, index) {
                      final card = allCards[index];
                      final file = File(card.frontImagePath);

                      return ListTile(
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
                                  InsuranceCardDetail(card: card),
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