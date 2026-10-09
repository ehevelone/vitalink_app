import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/deep_link_service.dart';
import '../services/profile_share_crypto_service.dart';
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
  final ProfileShareCryptoService _crypto = ProfileShareCryptoService();
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
      _codeCtrl.text = args.trim();
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _acceptAndLoad() async {
    final token = _codeCtrl.text.trim();

    if (token.isEmpty) {
      setState(() => _message = AppStrings.of(context).enterInviteCodeFirst);
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
        _message = AppStrings.of(context).logInBeforeAcceptingInvite;
      });
      return;
    }

    late final ({String inviteCode, String encodedKey}) parsed;
    try {
      parsed = _crypto.parseInviteToken(token);
    } on FormatException catch (e) {
      setState(() {
        _working = false;
        _message = e.message;
      });
      return;
    }

    final accept = await ApiService.acceptProfileShareLink(
      userId: userId,
      inviteCode: parsed.inviteCode,
    );

    if (!mounted) return;

    if (accept['success'] != true) {
      setState(() {
        _working = false;
        _message =
            (accept['error'] ?? AppStrings.of(context).unableToAcceptInvite)
                .toString();
      });
      return;
    }

    final share = Map<String, dynamic>.from(accept['share'] as Map? ?? {});
    final shareId = share['id']?.toString() ?? '';
    if (shareId.isEmpty) {
      setState(() {
        _working = false;
        _message = AppStrings.of(context).inviteCouldNotComplete;
      });
      return;
    }
    await _crypto.storeKey(shareId, parsed.encodedKey);

    final packages = await _loadPendingPackages(userId);

    if (!mounted) return;

    if (packages.isEmpty) {
      setState(() {
        _working = false;
        _message = AppStrings.of(context).profileInviteAccepted;
      });
      return;
    }

    for (final item in packages) {
      final packageId = item['packageId']?.toString() ?? '';
      final itemShareId = item['shareId']?.toString() ?? '';
      final encryptedPayload = item['encryptedPayload']?.toString() ?? '';
      final key =
          itemShareId.isEmpty ? null : await _crypto.loadKey(itemShareId);
      if (key == null || key.isEmpty || encryptedPayload.isEmpty) continue;
      Map<String, dynamic> packagePayload;
      try {
        packagePayload = await _crypto.decryptJson(encryptedPayload, key);
      } catch (_) {
        continue;
      }
      final updatePayload =
          Map<String, dynamic>.from(packagePayload['payload'] as Map? ?? {});
      updatePayload['_shareRelationshipId'] = itemShareId;

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
      _message = AppStrings.of(context).sharedProfileAdded;
    });

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppStrings.of(context).profileAdded,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          AppStrings.of(context).sharedProfileAddedSwitch,
          style: const TextStyle(color: Colors.white70),
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
        title: Text(AppStrings.of(context).addProfileFromInvite),
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
                  Text(
                    AppStrings.of(context).profileInvite,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.of(context).enterInviteCodeExplainer,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).inviteCode,
                      labelStyle: const TextStyle(color: Colors.white70),
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
                        _working
                            ? AppStrings.of(context).addingProfile
                            : AppStrings.of(context).addSharedProfile,
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
        border:
            Border.all(color: const Color(0xFF78C7E7).withValues(alpha: .35)),
      ),
      child: child,
    );
  }
}
