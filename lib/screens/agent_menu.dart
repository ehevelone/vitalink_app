import 'package:flutter/material.dart';

import '../services/secure_store.dart';
import '../models.dart';
import '../services/data_repository.dart';

class AgentMenuScreen extends StatefulWidget {
  const AgentMenuScreen({super.key});

  @override
  State<AgentMenuScreen> createState() => _AgentMenuScreenState();
}

class _AgentMenuScreenState extends State<AgentMenuScreen> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;
  String agentName = "Agent";

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _loadData();
  }

  Future<void> _loadData() async {
    final store = SecureStore();
    final p = await _repo.loadProfile();
    final storedName = await store.getString("agentName");

    setState(() {
      _p = p;
      agentName = storedName?.isNotEmpty == true ? storedName! : "Agent";
      _loading = false;
    });
  }

  Future<void> _logout(BuildContext context) async {
    final store = SecureStore();
    await store.remove('loggedIn');
    await store.remove('userLoggedIn');
    await store.remove('agentLoggedIn');
    await store.remove('role');
    await store.remove('authToken');
    await store.remove('device_token');

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/landing');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: Text(
          "Welcome $agentName",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset("assets/images/app_icon_big.png", height: 32),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Opacity(
                opacity: 0.06,
                child: Image.asset(
                  "assets/images/logo_icon.png",
                  width: MediaQuery.of(context).size.width * 0.9,
                ),
              ),
            ),

            _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          children: [
                            _item(Icons.badge, "My Agent", '/my_agent_agent'),
                            _item(Icons.person, "My Profile", '/my_profile'),
                            _item(Icons.medical_information, "Medications", '/meds'),
                            _item(Icons.people, "Doctors", '/doctors'),
                            _item(Icons.credit_card, "Insurance Cards",
                                '/insurance_cards_menu'),
                            _item(Icons.policy, "Insurance Policies",
                                '/insurance_policies'),
                          ],
                        ),
                      ),

                      /// ⭐ Emergency + Logout ONLY
                      SafeArea(
                        top: false,
                        minimum: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              // 🔥 Emergency Info
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade900,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  icon: const Icon(Icons.warning_amber_rounded),
                                  label: const Text(
                                    "Emergency Info",
                                    style: TextStyle(fontSize: 17),
                                  ),
                                  onPressed: () =>
                                      Navigator.pushNamed(context, '/emergency'),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // 🔓 Logout
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade100,
                                    foregroundColor: Colors.red.shade700,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  icon: const Icon(Icons.logout),
                                  label: const Text(
                                    "Log Out",
                                    style: TextStyle(fontSize: 17),
                                  ),
                                  onPressed: () => _logout(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String text, String route) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      color: const Color(0xFFF7F1FF),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(text, style: const TextStyle(fontSize: 18)),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}
