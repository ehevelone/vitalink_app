import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/api_service.dart';
import '../services/secure_store.dart';

enum _AgentItemType { note, task }

class AgentNotesScreen extends StatefulWidget {
  const AgentNotesScreen({super.key});

  @override
  State<AgentNotesScreen> createState() => _AgentNotesScreenState();
}

class _AgentNotesScreenState extends State<AgentNotesScreen> {
  final TextEditingController _textController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  int? _agentId;
  int? _selectedClientId;
  _AgentItemType _type = _AgentItemType.note;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _items = [];

  bool _loading = true;
  bool _saving = false;
  bool _listLoading = false;
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadScreen();
  }

  @override
  void dispose() {
    _textController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _loadScreen() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final agentIdStr = await SecureStore().getString("agentId");
      final agentId = int.tryParse(agentIdStr ?? "");

      if (agentId == null) {
        setState(() {
          _error = "Missing agent session";
          _loading = false;
        });
        return;
      }

      final res = await ApiService.getAgentClients(agentId: agentId);

      if (res["success"] != true) {
        setState(() {
          _error = res["error"] ?? "Failed to load clients";
          _loading = false;
        });
        return;
      }

      final clients = (res["clients"] as List? ?? [])
          .whereType<Map>()
          .map((c) => Map<String, dynamic>.from(c))
          .toList();

      setState(() {
        _agentId = agentId;
        _clients = clients;
        _selectedClientId =
            clients.isNotEmpty ? _asInt(clients.first["id"]) : null;
        _loading = false;
      });

      await _loadItems();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Failed to load notes and tasks";
        _loading = false;
      });
    }
  }

  Future<void> _loadItems() async {
    final agentId = _agentId;
    if (agentId == null) return;

    setState(() => _listLoading = true);

    try {
      final res = await ApiService.getAgentItems(
        agentId: agentId,
        clientId: _selectedClientId,
      );

      if (!mounted) return;

      if (res["success"] == true) {
        setState(() {
          _items = (res["items"] as List? ?? [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          _listLoading = false;
        });
      } else {
        setState(() {
          _items = [];
          _listLoading = false;
        });
        _showMessage(res["error"] ?? "Failed to load saved items");
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _listLoading = false);
      _showMessage("Failed to load saved items");
    }
  }

  Future<void> _saveItem() async {
    final agentId = _agentId;
    final clientId = _selectedClientId;
    final text = _textController.text.trim();

    if (agentId == null || clientId == null) {
      _showMessage("Choose a client first");
      return;
    }

    if (text.isEmpty) {
      _showMessage("Add note or task text first");
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await ApiService.saveAgentItem(
        agentId: agentId,
        clientId: clientId,
        itemType: _type.name,
        text: text,
      );

      if (!mounted) return;

      if (res["success"] == true) {
        _textController.clear();
        await _loadItems();
        _showMessage(_type == _AgentItemType.note ? "Note saved" : "Task saved");
      } else {
        _showMessage(res["error"] ?? "Failed to save");
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage("Failed to save");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      _showMessage("Microphone permission is needed for dictation");
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == "done" || status == "notListening") && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );

    if (!available) {
      _showMessage("Voice dictation is not available on this device");
      return;
    }

    setState(() => _listening = true);

    await _speech.listen(
      // ignore: deprecated_member_use
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;

        final current = _textController.text.trim();
        _textController.text = current.isEmpty ? words : "$current $words";
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
      },
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? "");
  }

  String _clientName(Map<String, dynamic> client) {
    final first = (client["first_name"] ?? "").toString().trim();
    final last = (client["last_name"] ?? "").toString().trim();
    final email = (client["email"] ?? "").toString().trim();
    final name = "$first $last".trim();
    return name.isNotEmpty ? name : email;
  }

  String _itemClientName(Map<String, dynamic> item) {
    final first = (item["first_name"] ?? "").toString().trim();
    final last = (item["last_name"] ?? "").toString().trim();
    final name = "$first $last".trim();
    return name.isNotEmpty ? name : (item["email"] ?? "Client").toString();
  }

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? "")?.toLocal();
    if (date == null) return "";

    final hour = date.hour == 0
        ? 12
        : date.hour > 12
            ? date.hour - 12
            : date.hour;
    final minute = date.minute.toString().padLeft(2, "0");
    final period = date.hour >= 12 ? "PM" : "AM";

    return "${date.month}/${date.day}/${date.year} $hour:$minute $period";
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: const Text(
          "Notes / Tasks",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(child: Text(_error!))
            else
              RefreshIndicator(
                onRefresh: _loadItems,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildComposer(),
                    const SizedBox(height: 16),
                    _buildSavedList(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _selectedClientId,
              decoration: InputDecoration(
                labelText: "Client",
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              items: _clients
                  .map(
                    (client) => DropdownMenuItem<int>(
                      value: _asInt(client["id"]),
                      child: Text(
                        _clientName(client),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedClientId = value);
                _loadItems();
              },
            ),
            const SizedBox(height: 14),
            SegmentedButton<_AgentItemType>(
              segments: const [
                ButtonSegment(
                  value: _AgentItemType.note,
                  icon: Icon(Icons.notes),
                  label: Text("Note"),
                ),
                ButtonSegment(
                  value: _AgentItemType.task,
                  icon: Icon(Icons.task_alt),
                  label: Text("Task"),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                setState(() => _type = selection.first);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _textController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: _type == _AgentItemType.note
                    ? "Enter note..."
                    : "Enter task...",
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: _saving ? null : _saveItem,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? "Saving..." : "Save"),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    color: _listening ? Colors.red.shade700 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: IconButton(
                    onPressed: _toggleVoice,
                    icon: Icon(
                      _listening ? Icons.mic_off : Icons.mic,
                      color: _listening ? Colors.white : Colors.red.shade700,
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

  Widget _buildSavedList() {
    if (_clients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Text(
            "No clients found",
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    if (_listLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Text(
            "No saved notes or tasks",
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Column(
      children: _items.map((item) {
        final isTask = item["item_type"] == "task";
        final color = isTask ? Colors.orange.shade700 : Colors.blue.shade700;

        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(isTask ? Icons.task_alt : Icons.notes, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isTask ? "Task" : "Note",
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _itemClientName(item),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (item["body"] ?? "").toString(),
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _dateLabel(item["created_at"]),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
