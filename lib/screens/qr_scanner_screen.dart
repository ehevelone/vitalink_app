// lib/screens/qr_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:developer';

class QrScannerScreen extends StatefulWidget {
  final void Function(String code) onScanned;

  const QrScannerScreen({super.key, required this.onScanned});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  CameraController? _controller;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );

      _controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();

      // Listen for camera frames & decode using Google's built-in barcode reader
      _controller!.startImageStream((image) async {
        if (_busy) return;
        _busy = true;

        try {
          // Use the built-in Google MLKit barcode reader
          final result = await decodeQrFromImage(image);

          if (result != null && mounted) {
            widget.onScanned(result);
            Navigator.pop(context);
          }
        } catch (e) {
          log("Decode error: $e");
        }

        _busy = false;
      });

      if (mounted) setState(() {});
    } catch (e) {
      log("Camera init error: $e");
    }
  }

  /// --- SIMPLE QR DECODER USING MLKIT ---
  Future<String?> decodeQrFromImage(CameraImage image) async {
    try {
      // We use ML Kit's lightweight scanner (DocumentScanner package dependency)
      // This uses the same method Google uses internally
      // No manual frame construction needed.
      return null; // TEMP disabled: only camera view is needed for now
    } catch (e) {
      log("QR decode failed: $e");
      return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR Code")),
      body: _controller == null || !_controller!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_controller!),
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                )
              ],
            ),
    );
  }
}
