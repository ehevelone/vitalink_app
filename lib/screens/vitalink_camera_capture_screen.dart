import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class VitalinkCameraCaptureScreen extends StatefulWidget {
  final String title;
  final String reviewTitle;
  final String instructions;
  final String addAnotherLabel;
  final int maxPhotos;

  const VitalinkCameraCaptureScreen({
    super.key,
    required this.title,
    required this.reviewTitle,
    required this.instructions,
    this.addAnotherLabel = 'Add Another Side',
    this.maxPhotos = 4,
  });

  @override
  State<VitalinkCameraCaptureScreen> createState() =>
      _VitalinkCameraCaptureScreenState();
}

class _VitalinkCameraCaptureScreenState
    extends State<VitalinkCameraCaptureScreen> {
  static const Color _vitalinkBlue = Color(0xFF79CAE3);

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  final List<String> _acceptedPaths = [];
  String? _previewPath;
  bool _loading = true;
  bool _takingPicture = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _error = 'No camera was found on this device.';
          _loading = false;
        });
        return;
      }

      final backCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Camera could not be opened. Please check camera permission.';
        _loading = false;
      });
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _takingPicture) {
      return;
    }

    setState(() => _takingPicture = true);

    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      setState(() => _previewPath = file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  void _usePhoto({required bool addAnother}) {
    final path = _previewPath;
    if (path == null) return;

    _acceptedPaths.add(path);

    if (!addAnother || _acceptedPaths.length >= widget.maxPhotos) {
      Navigator.pop(context, List<String>.from(_acceptedPaths));
      return;
    }

    setState(() => _previewPath = null);
  }

  void _finishWithoutCurrent() {
    if (_acceptedPaths.isEmpty) {
      Navigator.pop(context, <String>[]);
    } else {
      Navigator.pop(context, List<String>.from(_acceptedPaths));
    }
  }

  Widget _actionButton({
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
    IconData? icon,
  }) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );

    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _vitalinkBlue,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: child,
    );
  }

  Widget _buildPreview() {
    final path = _previewPath!;
    final canAddMore = _acceptedPaths.length + 1 < widget.maxPhotos;

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.reviewTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'If the image is blurry, dark, or cut off, retake it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                _actionButton(
                  label: 'Use Photo',
                  primary: true,
                  icon: Icons.check,
                  onPressed: () => _usePhoto(addAnother: false),
                ),
                if (canAddMore) ...[
                  const SizedBox(height: 10),
                  _actionButton(
                    label: widget.addAnotherLabel,
                    icon: Icons.add_a_photo,
                    onPressed: () => _usePhoto(addAnother: true),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        label: 'Retake',
                        icon: Icons.refresh,
                        onPressed: () => setState(() => _previewPath = null),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _actionButton(
                        label: 'Cancel',
                        icon: Icons.close,
                        onPressed: _finishWithoutCurrent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCamera() {
    final controller = _controller;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 17),
          ),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: Center(
              child: CameraPreview(controller),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.instructions,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                if (_acceptedPaths.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_acceptedPaths.length} photo(s) added',
                    style: const TextStyle(
                      color: _vitalinkBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _actionButton(
                  label: _takingPicture ? 'Taking Photo...' : 'Take Photo',
                  primary: true,
                  icon: Icons.camera_alt,
                  onPressed: _takingPicture ? null : _takePicture,
                ),
                const SizedBox(height: 10),
                _actionButton(
                  label: _acceptedPaths.isEmpty ? 'Cancel' : 'Done',
                  icon: _acceptedPaths.isEmpty ? Icons.close : Icons.check,
                  onPressed: _finishWithoutCurrent,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title)),
      body: _previewPath == null ? _buildCamera() : _buildPreview(),
    );
  }
}
