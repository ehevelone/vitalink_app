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
    } catch (e) {
      print("LOAD ERROR: $e");
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
    print("---- SCAN BUTTON PRESSED ----");
    print("Platform detected: $defaultTargetPlatform");

    final status = await Permission.camera.request();
    print("Camera permission status: $status");

    if (!status.isGranted) {
      print("Permission NOT granted.");
      return;
    }

    try {
      String? imagePath;

      if (defaultTargetPlatform == TargetPlatform.android) {
        print("Android branch running");

        final scanner = DocumentScanner(
          options: DocumentScannerOptions(
            mode: ScannerMode.full,
            pageLimit: 1,
          ),
        );

        print("Launching MLKit scanner...");
        final result = await scanner.scanDocument();
        print("MLKit returned: $result");

        if (result == null ||
            result.images == null ||
            result.images!.isEmpty) {
          print("No images returned from MLKit");
          return;
        }

        imagePath = result.images!.first;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        print("iOS branch running");

        final isTablet =
            MediaQuery.of(context).size.shortestSide >= 600;

        print("Is tablet: $isTablet");

        if (isTablet) {
          print("Using ImagePicker camera for iPad...");
          final picker = ImagePicker();
          final file =
              await picker.pickImage(source: ImageSource.camera);

          print("ImagePicker returned: $file");

          if (file == null) return;
          imagePath = file.path;
        } else {
          print("Using CunningDocumentScanner for iPhone...");
          final images =
              await CunningDocumentScanner.getPictures();

          print("Cunning returned: $images");

          if (images == null || images.isEmpty) return;
          imagePath = images.first;
        }
      } else {
        print("Unknown platform.");
        return;
      }

      if (imagePath == null) {
        print("Image path is null.");
        return;
      }

      print("Image path saved: $imagePath");

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
      print("Profile saved successfully.");

    } catch (e) {
      print("SCANNER ERROR: $e");
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