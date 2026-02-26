import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class IOSCardScanScreen extends StatefulWidget {
  const IOSCardScanScreen({super.key});

  @override
  State<IOSCardScanScreen> createState() =>
      _IOSCardScanScreenState();
}

class _IOSCardScanScreenState
    extends State<IOSCardScanScreen> {
  final ImagePicker _picker = ImagePicker();
  late final DataRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _startScan();
  }

  Future<void> _startScan() async {
    final file =
        await _picker.pickImage(source: ImageSource.camera);

    if (file != null) {
      final profile = await _repo.loadProfile();
      if (profile != null) {
        profile.orphanCards.add(
          InsuranceCard(
            frontImagePath: file.path,
            carrier: "",
            policy: "",
          ),
        );
        await _repo.saveProfile(profile);
      }
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}