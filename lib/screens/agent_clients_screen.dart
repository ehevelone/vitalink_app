import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
      final unlockCode = await store.getString("unlock_code");

      if (unlockCode == null) {
        setState(() {
          error = "Missing agent code";
          loading = false;
        });
        return;
      }

      final res = await http.post(
        Uri.parse(
          "https://vitalink-app.netlify.app/.netlify/functions/get-agent-clients",
        ),
        headers: {
          "Content-Type": "application/json"
        },
        body: jsonEncode({
          "unlock_code": unlockCode
        }),
      );

      final data = jsonDecode(res.body);

      setState(() {
        clients = data["clients"] ?? [];
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
                        final active = client["active"] == true;

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
                            subtitle: Text(
                              active ? "Active" : "Inactive",
                            ),
                            trailing: Icon(
                              active
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: active
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}