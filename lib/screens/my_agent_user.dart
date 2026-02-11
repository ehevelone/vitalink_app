import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/secure_store.dart';
import '../services/data_repository.dart';
import '../models.dart';

class MyAgentUser extends StatefulWidget {
  const MyAgentUser({super.key});

  @override
  State<MyAgentUser> createState() => _MyAgentUserState();
}

class _MyAgentUserState extends State<MyAgentUser> {
  String? _agentName;
  String? _agentPhone;
  String? _agentEmail;
  String? _agentNpn;
  String? _agencyName;
  String? _agencyAddress;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  Future<void> _loadAgent() async {
    final store = SecureStore();
    final repo = DataRepository(store);
    final profile = await repo.loadProfile();

    _agentName =
        (await store.getString("agentName")) as String?
            ?? profile?.agentName as String?;

    _agentPhone =
        (await store.getString("agentPhone")) as String?
            ?? profile?.agentPhone as String?;

    _agentEmail =
        (await store.getString("agentEmail")) as String?
            ?? profile?.agentEmail as String?;

    _agentNpn =
        (await store.getString("agentId")) as String?
            ?? profile?.agentId as String?;

    _agencyName =
        (await store.getString("agencyName")) as String?;

    _agencyAddress =
        (await store.getString("agencyAddress")) as String?;

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _sendToAgent() async {
    Navigator.pushNamed(context, '/authorization_form');
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: const Text(
          "My Agent",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Opacity(
                opacity: 0.18,
                child: Image.asset(
                  "assets/images/logo_icon.png",
                  width: MediaQuery.of(context).size.width * 0.9,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _agentName ?? "Unknown Agent",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),

                            if (_agentNpn?.isNotEmpty == true)
                              Text("NPN: $_agentNpn",
                                  style: const TextStyle(fontSize: 16)),

                            if (_agencyName?.isNotEmpty == true)
                              Text("🏢 ${_agencyName!}",
                                  style: const TextStyle(fontSize: 16)),

                            if (_agencyAddress?.isNotEmpty == true)
                              Text(
                                "📍 ${_agencyAddress!}",
                                style: const TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            const SizedBox(height: 8),

                            if (_agentPhone?.isNotEmpty == true)
                              InkWell(
                                onTap: _call,
                                child: Text(
                                  "📞 ${_agentPhone!}",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),

                            if (_agentEmail?.isNotEmpty == true)
                              InkWell(
                                onTap: _email,
                                child: Text(
                                  "📧 ${_agentEmail!}",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    ElevatedButton.icon(
                      onPressed: _loadAgent,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Reload Info"),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send),
                        label: const Text("Send My Info to Agent"),
                        onPressed: _sendToAgent,
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
