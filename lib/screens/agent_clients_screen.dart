import 'package:flutter/material.dart';

class AgentClientsScreen extends StatefulWidget {
  const AgentClientsScreen({super.key});

  @override
  State<AgentClientsScreen> createState() => _AgentClientsScreenState();
}

class _AgentClientsScreenState extends State<AgentClientsScreen> {

  // TEMP DATA (we will replace with API later)
  final List<Map<String, dynamic>> clients = [
    {
      "name": "John Smith",
      "status": "Active"
    },
    {
      "name": "Mary Johnson",
      "status": "Inactive"
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Clients"),
        backgroundColor: Colors.blue.shade700,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: clients.length,
        itemBuilder: (context, index) {

          final client = clients[index];

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
                client["name"],
                style: const TextStyle(fontSize: 18),
              ),
              subtitle: Text(client["status"]),
              trailing: IconButton(
                icon: const Icon(Icons.toggle_off),
                onPressed: () {
                  _toggleStatus(index);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _toggleStatus(int index) {

    setState(() {

      if (clients[index]["status"] == "Active") {
        clients[index]["status"] = "Inactive";
      } else {
        clients[index]["status"] = "Active";
      }

    });

  }
}