import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

class ScanCard extends StatefulWidget {
  const ScanCard({super.key});

  @override
  State<ScanCard> createState() => _ScanCardState();
}

class _ScanCardState extends State<ScanCard> {
  bool _scanning = false;

  Future<void> _startScan() async {
    setState(() => _scanning = true);

    DocumentScanner? scanner;
    try {
      final options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: 1,
        isGalleryImport: true,
      );

      scanner = DocumentScanner(options: options);

      final result = await scanner.scanDocument();
      final images = result?.images;

      if (!mounted) return;

      if (images != null && images.isNotEmpty) {
        Navigator.pop(context, images.first);
      } else {
        Navigator.pop(context, null);
      }
    } catch (e) {
      debugPrint("❌ Document scan failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Scan failed: $e")),
        );
      }
      Navigator.pop(context, null);
    } finally {
      try {
        await scanner?.close();
      } catch (_) {}

      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Insurance Card")),
      body: Center(
        child: _scanning
            ? const CircularProgressIndicator()
            : const Text("Preparing scanner..."),
      ),
    );
  }
}
