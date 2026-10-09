import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

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
          error = AppStrings.of(context).missingAgentSession;
          loading = false;
        });
        return;
      }

      final agentId = int.tryParse(agentIdStr);

      if (agentId == null) {
        setState(() {
          error = AppStrings.of(context).invalidAgentId;
          loading = false;
        });
        return;
      }

      final res = await ApiService.getAgentClients(agentId: agentId);

      if (res["success"] != true) {
        setState(() {
          error = res["error"] ?? AppStrings.of(context).failedToLoadClients;
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
        error = AppStrings.of(context).failedToLoadClients;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context).myClients),
        backgroundColor: Colors.blue.shade700,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : clients.isEmpty
                  ? Center(child: Text(AppStrings.of(context).noClientsFound))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: clients.length,
                      itemBuilder: (context, index) {
                        final client = clients[index];

                        final first = client["first_name"] ?? "";
                        final last = client["last_name"] ?? "";
                        final email = client["email"] ?? "";
                        final phone = client["phone"] ?? "";
                        final active = client["active"] == true;

                        // 🔥 NEW (SAFE ADD)
                        final hasDevice = client["has_device"] == true;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            tileColor: Colors.transparent,
                            shape: const Border(
                              bottom: BorderSide(color: Colors.black12),
                            ),
                            leading:
                                const Icon(Icons.person, color: Colors.blue),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "$first $last",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),

                                // 🔥 UPDATED (Active + Device Icon)
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? Colors.green.shade100
                                            : Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        active
                                            ? AppStrings.of(context).activeLabel
                                            : AppStrings.of(context)
                                                .inactiveLabel,
                                        style: TextStyle(
                                          color: active
                                              ? Colors.green.shade800
                                              : Colors.red.shade800,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      hasDevice
                                          ? Icons.phone_android
                                          : Icons.phone_disabled,
                                      size: 18,
                                      color:
                                          hasDevice ? Colors.green : Colors.red,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(email),
                                Text(phone),

                                // 🔥 OPTIONAL DEBUG LINE (safe)
                                Text(
                                  AppStrings.of(context).deviceYesNo(hasDevice),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        hasDevice ? Colors.green : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
