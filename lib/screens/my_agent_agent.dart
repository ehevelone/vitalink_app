import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';

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

        await store.setString("agentName", _agentName ?? "");
        await store.setString("agentEmail", _agentEmail ?? "");
        await store.setString("agentPhone", _agentPhone ?? "");
        await store.setString("agentNpn", _agentNpn ?? "");
        await store.setString("agencyName", _agencyName ?? "");
        await store.setString("agencyAddress", _agencyAddress ?? "");
      } else {
        _agentName = await store.getString("agentName");
        _agentEmail ??= await store.getString("agentEmail");
        _agentPhone = await store.getString("agentPhone");
        _agentNpn = await store.getString("agentNpn");
        _agencyName = await store.getString("agencyName");
        _agencyAddress = await store.getString("agencyAddress");
      }

      final res =
          await ApiService.getAgentPromoCode(_agentEmail ?? "");

      if (res['success'] == true) {
        final code = res['promoCode'];
        await store.setString("agentPromoCode", code);
        _promoCode = code;
        _deepLink =
            "https://vitalink-app.netlify.app/onboard?code=$code";
      }

      final stored = await store.getString("agentPromoCode");
      if (_promoCode == null && stored != null) {
        _promoCode = stored;
        _deepLink =
            "https://vitalink-app.netlify.app/onboard?code=$stored";
      }
    } catch (_) {
      _agentName = await store.getString("agentName");
      _agentEmail ??= await store.getString("agentEmail");
      _agentPhone = await store.getString("agentPhone");
      _agentNpn = await store.getString("agentNpn");
      _agencyName = await store.getString("agencyName");
      _agencyAddress = await store.getString("agencyAddress");
    }

    setState(() => _loading = false);
  }

  Future<void> _copyInviteLink() async {
    if (_deepLink == null) return;
    await Clipboard.setData(ClipboardData(text: _deepLink!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Invite link copied 📋")),
    );
  }

  // 🔔 UPDATED: Now shows dialog with full results
  Future<void> _sendNotification() async {
    if (_agentEmail == null || _agentEmail!.isEmpty) return;

    setState(() => _loading = true);

    final res =
        await ApiService.sendNotification(agentEmail: _agentEmail!);

    setState(() => _loading = false);

    if (!mounted) return;

    final success = res["success"] == true;
    final campaign = res["campaign"] ?? "";
    final total = res["totalDevices"] ?? 0;
    final notified = res["notifiedUsers"] ?? 0;
    final failures = res["failureCount"] ?? 0;
    final message = res["message"];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(success ? "Notification Results" : "Error"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!success)
              Text(res["error"] ?? "Unknown error")
            else ...[
              if (message != null) Text(message),
              if (campaign.isNotEmpty)
                Text("Campaign: $campaign"),
              const SizedBox(height: 8),
              Text("Devices targeted: $total"),
              Text("Users notified: $notified"),
              Text("Failures: $failures"),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _goToAuthorizationForm() async {
    await Navigator.pushNamed(context, '/authorization_form');
    await _loadAgentInfo();
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
          "My Agent – $displayName",
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
                        child: Column(
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (_agencyName?.isNotEmpty == true)
                              Text("🏢 $_agencyName"),
                            if (_agencyAddress?.isNotEmpty == true)
                              Text("📍 $_agencyAddress"),
                            if (_agentPhone?.isNotEmpty == true)
                              Text("📞 $_agentPhone"),
                            if (_agentEmail?.isNotEmpty == true)
                              Text("📧 $_agentEmail"),
                          ],
                        ),
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
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.copy),
                                  label: const Text("Copy Invite Link"),
                                  onPressed: _copyInviteLink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.assignment),
                        label: const Text("Send My Information"),
                        onPressed: _goToAuthorizationForm,
                      ),
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.notifications_active),
                        label: const Text("Send Notification"),
                        onPressed: _sendNotification,
                      ),
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
}