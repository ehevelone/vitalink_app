import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // (unused but left per your setup)
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;              // ✅ ADDED
import 'package:path_provider/path_provider.dart';    // ✅ ADDED

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class InsuranceCardDetail extends StatefulWidget {
  final InsuranceCard card;
  final VoidCallback? onDelete;
  final bool startOnBack;

  const InsuranceCardDetail({
    super.key,
    required this.card,
    this.onDelete,
    this.startOnBack = false,
  });

  @override
  State<InsuranceCardDetail> createState() => _InsuranceCardDetailState();
}

class _InsuranceCardDetailState extends State<InsuranceCardDetail> {
  bool _showFront = true;
  final ImagePicker _picker = ImagePicker();
  late final DataRepository _repo;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _showFront = !widget.startOnBack;
  }

  void _toggleView() {
    if ((widget.card.backImagePath ?? '').isNotEmpty) {
      setState(() => _showFront = !_showFront);
    }
  }

  // ✅ NEW: SEND AS PDF
  Future<void> _sendInsuranceEmail() async {
    final card = widget.card;

    final frontPath = card.frontImagePath;
    final backPath = card.backImagePath;

    if (frontPath.isEmpty && (backPath == null || backPath.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No card images available")),
      );
      return;
    }

    final pdf = pw.Document();

    final frontImage = File(frontPath).existsSync()
        ? pw.MemoryImage(File(frontPath).readAsBytesSync())
        : null;

    final backImage = (backPath != null &&
            backPath.isNotEmpty &&
            File(backPath).existsSync())
        ? pw.MemoryImage(File(backPath).readAsBytesSync())
        : null;

    if (frontImage != null) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) =>
              pw.Center(child: pw.Image(frontImage)),
        ),
      );
    }

    if (backImage != null) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) =>
              pw.Center(child: pw.Image(backImage)),
        ),
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
        "${dir.path}/insurance_card_${DateTime.now().millisecondsSinceEpoch}.pdf");

    await file.writeAsBytes(await pdf.save());

    final subject =
        "Insurance Card – ${card.carrier.isNotEmpty ? card.carrier : "Member"}";

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      text: "Please find my insurance card attached for your records.",
    );
  }

  Future<void> _captureBack() async {
    try {
      final XFile? image =
          await _picker.pickImage(source: ImageSource.camera);
      if (image == null) return;

      File file = File(image.path);
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      const url =
          "https://vitalink-app.netlify.app/.netlify/functions/parse_cards";

      final resp = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"imageBase64": base64Image}),
      );

      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);

        String finalPath = file.path;

        if (parsed['card_image_base64'] != null) {
          try {
            final croppedBytes =
                base64Decode(parsed['card_image_base64']);
            final croppedFile =
                await File('${file.path}_back_cropped.png')
                    .writeAsBytes(croppedBytes);
            finalPath = croppedFile.path;
          } catch (_) {}
        }

        if (!mounted) return;

        setState(() {
          widget.card.backImagePath = finalPath;
          _showFront = false;
        });

        final profile = await _repo.loadProfile();
        if (profile != null) {
          bool updated = false;

          for (var i = 0; i < profile.orphanCards.length; i++) {
            if (profile.orphanCards[i] == widget.card) {
              profile.orphanCards[i] = widget.card;
              updated = true;
              break;
            }
          }

          for (var ins in profile.insurances) {
            for (var i = 0; i < ins.cards.length; i++) {
              if (ins.cards[i] == widget.card) {
                ins.cards[i] = widget.card;
                updated = true;
                break;
              }
            }
          }

          if (updated) {
            profile.updatedAt = DateTime.now();
            await _repo.saveProfile(profile);
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;

    final imagePath = _showFront
        ? card.frontImagePath
        : (card.backImagePath ?? '');

    final file = (imagePath.isNotEmpty)
        ? File(imagePath)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          card.carrier.isNotEmpty
              ? card.carrier
              : "Insurance Card",
        ),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: widget.onDelete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: (file != null && file.existsSync())
                  ? GestureDetector(
                      onTapUp: (_) {
                        if (_currentScale == 1.0) {
                          _toggleView();
                        }
                      },
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 5.0,
                        onInteractionUpdate: (details) {
                          setState(
                              () => _currentScale = details.scale);
                        },
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  : const Icon(Icons.broken_image, size: 120),
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _captureBack,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        (card.backImagePath ?? '').isEmpty
                            ? "Add Back of Card"
                            : "Replace Back of Card",
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _sendInsuranceEmail,
                      icon: const Icon(Icons.email_outlined),
                      label: const Text("Share This Card"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}