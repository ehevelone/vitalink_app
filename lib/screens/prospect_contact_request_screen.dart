import 'dart:io';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

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
      setState(() => _error = AppStrings.of(context).pleaseSignInAgain);
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
          title: Text(AppStrings.of(context).requestSent),
          content: Text(AppStrings.of(context).agentHasBeenNotified(
              _args['agentName']?.toString() ??
                  AppStrings.of(context).yourAgent)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.of(context).done),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _sending = false;
      _error = result['error']?.toString() ??
          AppStrings.of(context).unableToSendRequest;
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
    final agentName =
        _args['agentName']?.toString() ?? AppStrings.of(context).yourAgent;
    final topic = AppStrings.of(context)
        .prospectTopicLabel(_args['topic']?.toString() ?? 'insurance');
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).contactMyAgent)),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            AppStrings.of(context).agentWouldLikeToHelp(agentName, topic),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Text(
            AppStrings.of(context).howToBeContacted,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _choice('call', AppStrings.of(context).callMe, Icons.phone_outlined),
          _choice('text', AppStrings.of(context).textMe, Icons.sms_outlined),
          _choice(
              'email', AppStrings.of(context).emailMe, Icons.email_outlined),
          const SizedBox(height: 14),
          Text(
            AppStrings.of(context).agentMayContactAbout(agentName, topic),
            style: const TextStyle(color: Colors.black54, height: 1.35),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _channels.isEmpty || _sending ? null : _submit,
            child: Text(_sending
                ? AppStrings.of(context).sending
                : AppStrings.of(context).send),
          ),
        ],
      ),
    );
  }
}
