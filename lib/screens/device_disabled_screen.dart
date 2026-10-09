import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
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
        title: Text(AppStrings.of(context).eraseVitaLinkDataTitle),
        content: Text(
          AppStrings.of(context).eraseVitaLinkDataBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.of(context).keepData),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.of(context).eraseFromThisDevice),
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
                      Text(
                        AppStrings.of(context).deviceDisabledTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 25, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        replaced && !erased
                            ? AppStrings.of(context).deviceMovedBody
                            : lostOrStolen && erased
                                ? AppStrings.of(context).deviceLostStolenBody
                                : AppStrings.of(context).deviceDisabledBody,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, height: 1.4),
                      ),
                      if (replaced && !erased) ...[
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed: _eraseData,
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: Text(AppStrings.of(context).eraseVitaLinkData),
                        ),
                      ],
                      const SizedBox(height: 26),
                      ElevatedButton(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/login',
                          (route) => false,
                        ),
                        child: Text(AppStrings.of(context).returnToLogin),
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
