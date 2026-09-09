import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  static bool _checkedThisSession = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  Future<void> _checkForUpdate() async {
    if (_checkedThisSession || !mounted) return;
    _checkedThisSession = true;

    try {
      final update = await AppUpdateService.checkForUpdate();
      if (update == null || !mounted) return;

      final shouldShow = await AppUpdateService.shouldShow(update);
      if (!shouldShow || !mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !update.required,
        builder: (_) => _AppUpdateDialog(update: update),
      );
    } catch (_) {
      // Update checks must never block login or app use.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppUpdateDialog extends StatelessWidget {
  const _AppUpdateDialog({required this.update});

  final AppUpdateInfo update;

  Future<void> _openStore() async {
    final uri = Uri.tryParse(update.storeUrl);
    if (uri == null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final notes = update.releaseNotes.take(4).toList();

    return PopScope(
      canPop: !update.required,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF101820),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF78C7E7).withValues(alpha: .5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .45),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF78C7E7).withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.system_update_alt,
                      color: Color(0xFF78C7E7),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      update.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                update.message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 18),
                ...notes.map(
                  (note) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF78C7E7),
                          size: 19,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openStore,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF78C7E7),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text(
                    'Update VitaLink',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (!update.required) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () async {
                      await AppUpdateService.remindLater(update);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text(
                      'Remind me later',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
