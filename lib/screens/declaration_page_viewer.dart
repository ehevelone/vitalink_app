import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart'; // ✅ SAFE replacement
import '../widgets/app_header.dart';
import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class DeclarationPageViewer extends StatefulWidget {
  final String path;

  const DeclarationPageViewer({super.key, required this.path});

  @override
  State<DeclarationPageViewer> createState() => _DeclarationPageViewerState();
}

class _DeclarationPageViewerState extends State<DeclarationPageViewer> {
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
    final profile = await _repo.loadProfile();
    setState(() {
      _p = profile;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileName = (_p != null && _p!.fullName.isNotEmpty)
        ? " – ${_p!.fullName}"
        : "";

    final file = File(widget.path);

    return Scaffold(
      appBar: AppHeader(title: "Declaration Page$profileName"),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !file.existsSync()
              ? const Center(child: Text("File not found"))
              : _isPdf(widget.path)
                  ? _buildPdfView(file)
                  : _buildImageView(file),
    );
  }

  /// ✅ Check if path is a PDF
  bool _isPdf(String path) => path.toLowerCase().endsWith(".pdf");

  /// ✅ SAFE PDF viewer (NO native pdfium)
  Widget _buildPdfView(File file) {
    return PdfPreview(
      build: (format) async => await file.readAsBytes(),
      canChangePageFormat: false,
      canChangeOrientation: false,
      allowPrinting: false,
      allowSharing: false,
    );
  }

  /// ✅ Image viewer widget (unchanged)
  Widget _buildImageView(File file) {
    return InteractiveViewer(
      panEnabled: true,
      minScale: 0.5,
      maxScale: 4,
      child: Image.file(file),
    );
  }
}