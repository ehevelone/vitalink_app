import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/app_state.dart';

class MyAgentUser extends StatefulWidget {
  const MyAgentUser({super.key});

  @override
  State<MyAgentUser> createState() => _MyAgentUserState();
}

class _MyAgentUserState extends State<MyAgentUser> {
  String? _agentName;
  String? _agentPhone;
  String? _agentEmail;
  String? _agencyName;
  String? _agencyAddress;
  String? _calendlyUrl;
  String? _businessCardImageBase64;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  Future<void> _loadAgent() async {
    try {
      final userEmail = await AppState.getEmail();
      if (userEmail == null || userEmail.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final res = await ApiService.getUserAgent(userEmail);

      if (res["success"] == true && res["agent"] != null) {
        final agent = res["agent"];

        _agentName = agent["name"];
        _agentPhone = agent["phone"];
        _agentEmail = agent["email"];
        _agencyName = agent["agency_name"];
        _agencyAddress = agent["agency_address"];
        _calendlyUrl = agent["calendly_url"];
        _businessCardImageBase64 = agent["business_card_image_base64"];
      }
    } catch (e) {
      debugPrint("Agent load error: $e");
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _call() async {
    if (_agentPhone == null || _agentPhone!.isEmpty) return;
    final uri = Uri(scheme: "tel", path: _agentPhone);
    await launchUrl(uri);
  }

  Future<void> _email() async {
    if (_agentEmail == null || _agentEmail!.isEmpty) return;
    final uri = Uri(
      scheme: "mailto",
      path: _agentEmail,
      query: "subject=VitaLink%20Client%20Inquiry",
    );
    await launchUrl(uri);
  }

  Future<void> _sendToAgent() async {
    Navigator.pushNamed(context, '/authorization_form');
  }

  Future<void> _schedule() async {
    final url = _calendlyUrl?.trim();
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _agentCardDisplay() {
    final image = _businessCardImageBase64?.trim();
    if (image != null && image.isNotEmpty) {
      final bytes = base64Decode(image);
      return GestureDetector(
        onTap: () => _openBusinessCard(bytes),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _agentTextDisplay(),
          ),
        ),
      );
    }

    return _agentTextDisplay();
  }

  void _openBusinessCard(List<int> bytes) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agentTextDisplay() {
    return Column(
      children: [
        Text(
          _agentName ?? "No Agent Assigned",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (_agencyName?.isNotEmpty == true)
          Text("Agency: $_agencyName", textAlign: TextAlign.center),
        if (_agencyAddress?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Address: $_agencyAddress",
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 16),
        if (_agentPhone?.isNotEmpty == true)
          InkWell(
            onTap: _call,
            child: Text(
              "Phone: $_agentPhone",
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        if (_agentEmail?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              onTap: _email,
              child: Text(
                "Email: $_agentEmail",
                style: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text(
          "My Agent",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _agentCardDisplay(),
                  ),
                ),
                if (_calendlyUrl?.isNotEmpty == true) ...[
                  _actionButton(
                    icon: Icons.calendar_month,
                    label: "Schedule with My Agent",
                    light: true,
                    onPressed: _schedule,
                  ),
                  const SizedBox(height: 14),
                ],
                _actionButton(
                  icon: Icons.refresh,
                  label: "Reload Info",
                  onPressed: _loadAgent,
                ),
                const SizedBox(height: 20),
                _actionButton(
                  icon: Icons.send,
                  label: "Send My Info to Agent",
                  onPressed: _sendToAgent,
                ),
                const SizedBox(height: 14),
                _actionButton(
                  icon: Icons.favorite,
                  label: "Referral Center",
                  light: true,
                  onPressed: () => Navigator.pushNamed(
                    context,
                    '/referral_center',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool light = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor:
              light ? Colors.lightBlueAccent : Colors.blue.shade700,
          foregroundColor: light ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
