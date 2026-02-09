import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../models.dart';

class QrScreen extends StatefulWidget {
  final String data; // still passed in, NOT used for QR
  final String? title;

  const QrScreen({super.key, required this.data, this.title});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  /// 🔒 STATIC EMERGENCY PAGE — NO PARAMS, NO FUNCTIONS
  static const String _qrUrl =
      "https://vitalink.app/public/emergency.html";

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.loadProfile();
    if (!mounted) return;
    setState(() {
      _p = p;
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const FullscreenQr(url: _qrUrl),
                        ),
                      );
                    },
                    child: QrImageView(
                      data: _qrUrl,
                      size: 260,
                      backgroundColor: Colors.white,
                    ),
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

class FullscreenQr extends StatelessWidget {
  final String url;
  const FullscreenQr({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: QrImageView(
          data: url,
          size: 400,
          eyeStyle: const QrEyeStyle(
            color: Colors.white,
            eyeShape: QrEyeShape.square,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            color: Colors.white,
            dataModuleShape: QrDataModuleShape.square,
          ),
        ),
      ),
    );
  }
}
