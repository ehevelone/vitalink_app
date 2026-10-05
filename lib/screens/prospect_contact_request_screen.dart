import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/secure_store.dart';

class ProspectContactRequestScreen extends StatefulWidget {
  const ProspectContactRequestScreen({super.key});

  @override
  State<ProspectContactRequestScreen> createState() =>
      _ProspectContactRequestScreenState();
}

class _ProspectContactRequestScreenState
    extends State<ProspectContactRequestScreen> {
  final Set<String> _channels = {};
  bool _sending = false;
  String? _error;

  Map<String, dynamic> get _args => Map<String, dynamic>.from(
        ModalRoute.of(context)?.settings.arguments as Map? ?? {},
      );

  Future<void> _submit() async {
    if (_channels.isEmpty || _sending) return;
    final userId = await SecureStore().getString('userId');
    if (userId == null || userId.isEmpty) {
      setState(() => _error = 'Please sign in again.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await ApiService.submitProspectContactRequest(
      userId: userId,
      deliveryId: _args['deliveryId']?.toString() ?? '',
      channels: _channels.toList(),
      platform: Platform.isIOS ? 'ios' : 'android',
    );
    if (!mounted) return;
    if (result['success'] == true) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Request sent'),
          content: Text('${_args['agentName'] ?? 'Your agent'} has been notified.'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _sending = false;
      _error = result['error']?.toString() ?? 'Unable to send your request.';
    });
  }

  Widget _choice(String value, String label, IconData icon) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _channels.contains(value),
      onChanged: _sending
          ? null
          : (selected) => setState(() {
                if (selected == true) {
                  _channels.add(value);
                } else {
                  _channels.remove(value);
                }
              }),
      secondary: Icon(icon),
      title: Text(label),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  @override
  Widget build(BuildContext context) {
    final agentName = _args['agentName']?.toString() ?? 'Your agent';
    final topic = _args['topic']?.toString() ?? 'insurance';
    return Scaffold(
      appBar: AppBar(title: const Text('Contact My Agent')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            '$agentName would like to help with $topic.',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text(
            'How would you like to be contacted?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _choice('call', 'Call me', Icons.phone_outlined),
          _choice('text', 'Text me', Icons.sms_outlined),
          _choice('email', 'Email me', Icons.email_outlined),
          const SizedBox(height: 14),
          Text(
            '$agentName may contact me about $topic using the methods I selected.',
            style: const TextStyle(color: Colors.black54, height: 1.35),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _channels.isEmpty || _sending ? null : _submit,
            child: Text(_sending ? 'Sending...' : 'Send'),
          ),
        ],
      ),
    );
  }
}
