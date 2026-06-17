import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';
import '../services/secure_store.dart';

class MyAgentAgent extends StatefulWidget {
  const MyAgentAgent({super.key});

  @override
  State<MyAgentAgent> createState() => _MyAgentAgentState();
}

class _MyAgentAgentState extends State<MyAgentAgent> {
  bool _loading = true;

  String? _agentName;
  String? _agentEmail;
  String? _agentPhone;
  String? _agentNpn;
  String? _agencyName;
  String? _agencyAddress;
  String? _promoCode;
  String? _deepLink;
  String? _businessCardImageBase64;

  @override
  void initState() {
    super.initState();
    _loadAgentInfo();
  }

  Future<void> _loadAgentInfo() async {
    final store = SecureStore();
    setState(() => _loading = true);

    try {
      _agentEmail = await store.getString("agentEmail");

      final profileRes = await ApiService.getAgentProfile(
        email: _agentEmail ?? "",
      );

      if (profileRes['success'] == true) {
        final data = profileRes['agent'];

        _agentName = data['name'];
        _agentEmail = data['email'];
        _agentPhone = data['phone'];
        _agentNpn = data['npn'];
        _agencyName = data['agency_name'];
        _agencyAddress = data['agency_address'];
        _businessCardImageBase64 = data['business_card_image_base64'];

        await store.setString("agentName", _agentName ?? "");
        await store.setString("agentEmail", _agentEmail ?? "");
        await store.setString("agentPhone", _agentPhone ?? "");
        await store.setString("agentNpn", _agentNpn ?? "");
        await store.setString("agencyName", _agencyName ?? "");
        await store.setString("agencyAddress", _agencyAddress ?? "");
        if (_businessCardImageBase64?.isNotEmpty == true) {
          await store.setString(
            "agentBusinessCardImage",
            _businessCardImageBase64!,
          );
        }
      } else {
        await _loadStoredAgentInfo(store);
      }

      final res = await ApiService.getAgentPromoCode(_agentEmail ?? "");

      if (res['success'] == true) {
        final code = res['promoCode'];
        await store.setString("agentPromoCode", code);
        _promoCode = code;
        _deepLink = "https://myvitalink.app/agent-success.html?code=$code";
      }

      final stored = await store.getString("agentPromoCode");
      if (_promoCode == null && stored != null) {
        _promoCode = stored;
        _deepLink =
            "https://myvitalink.app/agent-success.html?code=$stored";
      }
    } catch (_) {
      await _loadStoredAgentInfo(store);
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadStoredAgentInfo(SecureStore store) async {
    _agentName = await store.getString("agentName");
    _agentEmail ??= await store.getString("agentEmail");
    _agentPhone = await store.getString("agentPhone");
    _agentNpn = await store.getString("agentNpn");
    _agencyName = await store.getString("agencyName");
    _agencyAddress = await store.getString("agencyAddress");
    _businessCardImageBase64 =
        await store.getString("agentBusinessCardImage");
  }

  Future<void> _copyInviteLink() async {
    if (_deepLink == null) return;
    await Clipboard.setData(ClipboardData(text: _deepLink!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Invite link copied")),
    );
  }

  Future<void> _sendNotification() async {
    if (_agentEmail == null || _agentEmail!.isEmpty) return;

    setState(() => _loading = true);

    final res =
        await ApiService.sendNotification(agentEmail: _agentEmail!);

    if (!mounted) return;
    setState(() => _loading = false);

    final success = res["success"] == true;
    final campaign = res["campaign"] ?? "";
    final total = res["devicesTargeted"] ?? 0;
    final notified = res["successCount"] ?? 0;
    final failures = res["failureCount"] ?? 0;
    final message = res["message"];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          success ? "Notification Results" : "Error",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!success)
              Text(
                res["error"] ?? "Unknown error",
                style: const TextStyle(color: Colors.redAccent),
              )
            else ...[
              if (message != null)
                Text(message, style: const TextStyle(color: Colors.white70)),
              if (campaign.isNotEmpty)
                Text(
                  "Campaign: $campaign",
                  style: const TextStyle(color: Colors.white70),
                ),
              const SizedBox(height: 10),
              Text(
                "Devices targeted: $total",
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                "Users notified: $notified",
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                "Failures: $failures",
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue.shade400,
            ),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _goToAuthorizationForm() async {
    await Navigator.pushNamed(context, '/authorization_form');
    await _loadAgentInfo();
  }

  Future<void> _scanBusinessCard() async {
    await Navigator.pushNamed(
      context,
      '/my_profile_agent',
      arguments: {'autoScan': true},
    );
    await _loadAgentInfo();
  }

  Widget _agentCardDisplay(String displayName) {
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
            errorBuilder: (_, __, ___) => _agentTextDisplay(displayName),
          ),
        ),
      );
    }

    return _agentTextDisplay(displayName);
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

  Widget _agentTextDisplay(String displayName) {
    return Column(
      children: [
        Text(
          displayName,
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
          Text("Phone: $_agentPhone", textAlign: TextAlign.center),
        if (_agentEmail?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text("Email: $_agentEmail", textAlign: TextAlign.center),
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

    final displayName =
        (_agentName?.isNotEmpty == true) ? _agentName! : "Agent";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: Text(
          "My Agent - $displayName",
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Opacity(
                opacity: 0.12,
                child: Image.asset(
                  "assets/images/logo_icon.png",
                  width: MediaQuery.of(context).size.width * 0.9,
                ),
              ),
            ),
            RefreshIndicator(
              onRefresh: _loadAgentInfo,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: _agentCardDisplay(displayName),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_promoCode != null && _deepLink != null)
                      Card(
                        color: const Color(0xfff7eff9),
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(
                                _promoCode!,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              QrImageView(
                                data: _deepLink!,
                                size: 210,
                                version: QrVersions.auto,
                                backgroundColor: Colors.white,
                              ),
                              const SizedBox(height: 12),
                              SelectableText(
                                _deepLink!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _copyInviteLink,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.copy),
                                  label: const Text(
                                    "Copy Invite Link",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 28),

                    _actionButton(
                      icon: Icons.document_scanner,
                      label: "Scan Business Card",
                      onPressed: _scanBusinessCard,
                    ),
                    const SizedBox(height: 18),
                    _actionButton(
                      icon: Icons.assignment,
                      label: "Send My Information",
                      onPressed: _goToAuthorizationForm,
                    ),
                    const SizedBox(height: 18),
                    _actionButton(
                      icon: Icons.notifications_active,
                      label: "Send Notification",
                      onPressed: _sendNotification,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
