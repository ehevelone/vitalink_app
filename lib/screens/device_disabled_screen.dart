import 'package:flutter/material.dart';

import '../services/device_security_service.dart';

class DeviceDisabledScreen extends StatefulWidget {
  const DeviceDisabledScreen({super.key});

  @override
  State<DeviceDisabledScreen> createState() => _DeviceDisabledScreenState();
}

class _DeviceDisabledScreenState extends State<DeviceDisabledScreen> {
  late Future<({String reason, bool dataErased})> _details;

  @override
  void initState() {
    super.initState();
    _details = DeviceSecurityService.revocationDetails();
  }

  Future<void> _eraseData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase VitaLink data?'),
        content: const Text(
          'Confirm your profiles are available on the new device first. This permanently deletes VitaLink profiles and files from this old device and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Data'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erase From This Device'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DeviceSecurityService.erasePreservedLocalData();
    if (!mounted) return;
    setState(() => _details = DeviceSecurityService.revocationDetails());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: FutureBuilder<({String reason, bool dataErased})>(
                future: _details,
                builder: (context, snapshot) {
                  final details = snapshot.data;
                  final replaced = details?.reason == 'replaced';
                  final lostOrStolen =
                      details?.reason == 'lost' || details?.reason == 'stolen';
                  final erased = details?.dataErased == true;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Icon(Icons.phonelink_erase,
                      size: 72, color: Colors.red.shade700),
                  const SizedBox(height: 22),
                  const Text(
                    'This device has been disabled',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    replaced && !erased
                        ? 'VitaLink was moved to a new device. Your local profiles have not been erased from this old device.'
                        : lostOrStolen && erased
                            ? 'This device was reported lost or stolen. VitaLink access was disabled and locally stored VitaLink profiles were erased.'
                            : 'VitaLink access has been disabled on this device.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                  if (replaced && !erased) ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _eraseData,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Erase VitaLink Data'),
                    ),
                  ],
                  const SizedBox(height: 26),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    ),
                    child: const Text('Return to Login'),
                  ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
