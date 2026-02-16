import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../services/api_service.dart';

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

      // ✅ Pull agent directly from backend using user email
      final res = await ApiService.getUserAgent(userEmail);

      if (res["success"] == true && res["agent"] != null) {
        final agent = res["agent"];

        _agentName = agent["name"];
        _agentPhone = agent["phone"];
        _agentEmail = agent["email"];
        _agencyName = agent["agency_name"];
        _agencyAddress = agent["agency_address"];
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
                    child: Column(
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
                          Text("🏢 $_agencyName"),

                        if (_agencyAddress?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              "📍 $_agencyAddress",
                              textAlign: TextAlign.center,
                            ),
                          ),

                        const SizedBox(height: 16),

                        if (_agentPhone?.isNotEmpty == true)
                          InkWell(
                            onTap: _call,
                            child: Text(
                              "📞 $_agentPhone",
                              style: const TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),

                        if (_agentEmail?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: InkWell(
                              onTap: _email,
                              child: Text(
                                "📧 $_agentEmail",
                                style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
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
      ),
    );
  }
}
