import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../models.dart';

class QrScreen extends StatefulWidget {
  final String data;
  final String? title;

  const QrScreen({super.key, required this.data, this.title});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  String? _qrUrl;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.loadProfile();
    if (!mounted || p == null) return;

    // 🔐 Build emergency payload
    final payload = {
      "name": p.fullName,
      "dob": p.dob,
      "bloodType": p.bloodType,
      "allergies": p.allergies,
      "conditions": p.conditions,
      "organDonor": p.organDonor,
      "emergencyContactName": p.emergencyContactName,
      "emergencyContactPhone": p.emergencyContactPhone,
    };

    final encoded =
        base64UrlEncode(utf8.encode(jsonEncode(payload)));

    setState(() {
      _p = p;
      _qrUrl =
          "https://myvitalink.app/emergency.html?data=$encoded";
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _p?.fullName.isNotEmpty == true
        ? "${widget.title ?? "Emergency QR"} – ${_p!.fullName}"
        : widget.title ?? "Emergency QR";

    return Scaffold(
      appBar: AppBar(title: Text(titleText)),
      body: _loading || _qrUrl == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: QrImageView(
                    data: _qrUrl!,
                    size: 260,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Emergency Access",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Scan this QR code to view emergency information.\n\n"
                  "If the page shows “Session expired”, rescan the QR.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
            ),
    );
  }
}
