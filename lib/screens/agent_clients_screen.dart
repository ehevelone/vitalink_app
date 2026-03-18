import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/secure_store.dart';

class AgentClientsScreen extends StatefulWidget {
  const AgentClientsScreen({super.key});

  @override
  State<AgentClientsScreen> createState() => _AgentClientsScreenState();
}

class _AgentClientsScreenState extends State<AgentClientsScreen> {

  List clients = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {

    try {

      final store = SecureStore();
      final agentIdStr = await store.getString("agentId");

      if (agentIdStr == null) {
        setState(() {
          error = "Missing agent session";
          loading = false;
        });
        return;
      }

      final agentId = int.tryParse(agentIdStr);

      if (agentId == null) {
        setState(() {
          error = "Invalid agent ID";
          loading = false;
        });
        return;
      }

      final res = await ApiService.getAgentClients(agentId: agentId);

      if (res["success"] != true) {
        setState(() {
          error = res["error"] ?? "Failed to load clients";
          loading = false;
        });
        return;
      }

      setState(() {
        clients = res["clients"] ?? [];
        loading = false;
      });

    } catch (e) {

      setState(() {
        error = "Failed to load clients";
        loading = false;
      });

    }

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Clients"),
        backgroundColor: Colors.blue.shade700,
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : clients.isEmpty
                  ? const Center(child: Text("No clients found"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: clients.length,
                      itemBuilder: (context, index) {

                        final client = clients[index];

                        final first = client["first_name"] ?? "";
                        final last = client["last_name"] ?? "";
                        final email = client["email"] ?? "";
                        final phone = client["phone"] ?? "";

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          color: const Color(0xFFF7F1FF),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.person, color: Colors.blue),
                            title: Text(
                              "$first $last",
                              style: const TextStyle(fontSize: 18),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(email),
                                Text(phone),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}