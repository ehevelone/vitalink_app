import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/deep_link_service.dart';
import '../services/secure_store.dart';

class ProfileAcceptInviteScreen extends StatefulWidget {
  const ProfileAcceptInviteScreen({super.key});

  @override
  State<ProfileAcceptInviteScreen> createState() =>
      _ProfileAcceptInviteScreenState();
}

class _ProfileAcceptInviteScreenState extends State<ProfileAcceptInviteScreen> {
  final SecureStore _store = SecureStore();
  final DataRepository _repo = DataRepository();
  final TextEditingController _codeCtrl = TextEditingController();

  bool _working = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final code = VitaLinkDeepLink.shareCode;
    if (code != null && code.isNotEmpty) {
      _codeCtrl.text = code;
      VitaLinkDeepLink.clearShareCode();
      WidgetsBinding.instance.addPostFrameCallback((_) => _acceptAndLoad());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.trim().isNotEmpty && _codeCtrl.text.isEmpty) {
      _codeCtrl.text = args.trim().toUpperCase();
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _acceptAndLoad() async {
    final code = _codeCtrl.text.trim().toUpperCase();

    if (code.isEmpty) {
      setState(() => _message = 'Enter the profile invite code first.');
      return;
    }

    setState(() {
      _working = true;
      _message = null;
    });

    final userId = await _store.getString('userId');

    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      setState(() {
        _working = false;
        _message = 'Please log in before accepting a profile invite.';
      });
      return;
    }

    final accept = await ApiService.acceptProfileShareLink(
      userId: userId,
      inviteCode: code,
    );

    if (!mounted) return;

    if (accept['success'] != true) {
      setState(() {
        _working = false;
        _message =
            (accept['error'] ?? 'Unable to accept this profile invite.')
                .toString();
      });
      return;
    }

    final packages = await _loadPendingPackages(userId);

    if (!mounted) return;

    if (packages.isEmpty) {
      setState(() {
        _working = false;
        _message =
            'Profile invite accepted. The shared profile will appear when the sender sends the current profile update.';
      });
      return;
    }

    for (final item in packages) {
      final packageId = item['packageId']?.toString() ?? '';
      final packagePayload =
          Map<String, dynamic>.from(item['payload'] as Map? ?? {});
      final updatePayload =
          Map<String, dynamic>.from(packagePayload['payload'] as Map? ?? {});

      if (packageId.isEmpty || updatePayload.isEmpty) continue;

      await _repo.applySharedProfileUpdate(updatePayload);
      await ApiService.markProfileUpdateApplied(
        userId: userId,
        packageId: packageId,
      );
    }

    if (!mounted) return;

    setState(() {
      _working = false;
      _message = 'Shared profile added.';
    });

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Profile Added',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'The shared profile has been added. You can switch to it now.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF78C7E7),
              foregroundColor: Colors.black,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/profile_picker');
  }

  Future<List<Map<String, dynamic>>> _loadPendingPackages(String userId) async {
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final updates = await ApiService.getProfileUpdatePackages(userId: userId);
      final packages = updates['packages'] is List
          ? (updates['packages'] as List)
              .whereType<Map>()
              .map((p) => Map<String, dynamic>.from(p))
              .toList()
          : <Map<String, dynamic>>[];

      if (packages.isNotEmpty) return packages;

      if (attempt < 3) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }

    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Profile from Invite'),
        backgroundColor: const Color(0xFF0E5A88),
      ),
      body: Container(
        color: Colors.black,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profile Invite',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the invite code from a family member or caregiver to add their shared VitaLink profile.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Invite Code',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _working ? null : _acceptAndLoad,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF78C7E7),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        _working ? 'Adding Profile...' : 'Add Shared Profile',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_message != null)
              _card(
                child: Text(
                  _message!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (_working)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF78C7E7).withValues(alpha: .35)),
      ),
      child: child,
    );
  }
}
