import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';

class ScanCard extends StatefulWidget {
  const ScanCard({super.key});

  @override
  State<ScanCard> createState() => _ScanCardState();
}

class _ScanCardState extends State<ScanCard> {
  bool _scanning = false;

  Future<void> _startScan() async {
    setState(() => _scanning = true);

    try {
      // Small delay helps iOS present cleanly
      await Future.delayed(const Duration(milliseconds: 200));

      final images = await CunningDocumentScanner.getPictures();

      if (!mounted) return;

      if (images != null && images.isNotEmpty) {
        Navigator.pop(context, images.first);
      } else {
        Navigator.pop(context, null);
      }
    } catch (e) {
      debugPrint("Scan failed: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Scan failed: $e")),
        );
      }

      Navigator.pop(context, null);
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
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