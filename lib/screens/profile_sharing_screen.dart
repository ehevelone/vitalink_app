import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/deep_link_service.dart';
import '../services/profile_share_crypto_service.dart';
import '../services/profile_update_sync_service.dart';
import '../services/persistent_file_store.dart';
import '../services/secure_store.dart';

class ProfileSharingScreen extends StatefulWidget {
  const ProfileSharingScreen({super.key});

  @override
  State<ProfileSharingScreen> createState() => _ProfileSharingScreenState();
}

class _ProfileSharingScreenState extends State<ProfileSharingScreen> {
  final SecureStore _store = SecureStore();
  final DataRepository _repo = DataRepository();
  final ProfileShareCryptoService _crypto = ProfileShareCryptoService();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _inviteCtrl = TextEditingController();

  bool _emergency = true;
  bool _medications = true;
  bool _doctors = true;
  bool _insuranceCards = true;
  bool _policies = true;
  bool _appointments = false;
  bool _saving = false;
  bool _loadingShares = true;
  String? _lastInviteCode;
  String? _message;
  List<Map<String, dynamic>> _shares = [];

  @override
  void initState() {
    super.initState();
    final shareCode = VitaLinkDeepLink.shareCode;
    if (shareCode != null && shareCode.isNotEmpty) {
      _inviteCtrl.text = shareCode;
      VitaLinkDeepLink.clearShareCode();
    }
    _loadShares();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _inviteCtrl.dispose();
    super.dispose();
  }

  List<String> get _selectedSections {
    return [
      if (_emergency) 'emergency',
      if (_medications) 'medications',
      if (_doctors) 'doctors',
      if (_insuranceCards) 'insurance_cards',
      if (_policies) 'policies',
      if (_appointments) 'appointments',
    ];
  }

  Future<void> _loadShares() async {
    final userId = await _store.getString('userId');
    final profile = await _repo.loadProfile();

    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      setState(() => _loadingShares = false);
      return;
    }

    final res = await ApiService.getProfileShareLinks(
      userId: userId,
      profileId: profile.id,
    );

    if (!mounted) return;

    final shares = res['success'] == true && res['shares'] is List
        ? (res['shares'] as List)
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList()
        : <Map<String, dynamic>>[];
    for (final share in shares) {
      final shareId = share['id']?.toString() ?? '';
      final inviteCode = share['invite_code']?.toString() ?? '';
      final key = shareId.isEmpty ? null : await _crypto.loadKey(shareId);
      if (inviteCode.isNotEmpty && key != null && key.isNotEmpty) {
        share['invite_token'] = _crypto.makeInviteToken(inviteCode, key);
      }
    }
    if (!mounted) return;
    setState(() {
      _loadingShares = false;
      _shares = shares;
    });
  }

  Future<void> _createShareLink() async {
    if (_selectedSections.isEmpty) {
      _showMessage(AppStrings.of(context).chooseOneSectionToShare);
      return;
    }

    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (email.isEmpty || phone.isEmpty) {
      _showMessage(AppStrings.of(context).enterEmailAndPhoneForShare);
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
      _lastInviteCode = null;
    });

    final userId = await _store.getString('userId');
    final profile = await _repo.loadProfile();

    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      _showMessage(AppStrings.of(context).logInAgainBeforeSharing);
      setState(() => _saving = false);
      return;
    }

    final res = await ApiService.createProfileShareLink(
      userId: userId,
      profileId: profile.id,
      profileName: profile.fullName,
      email: email,
      phone: phone,
      allowedSections: _selectedSections,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      final share = Map<String, dynamic>.from(res['share'] as Map? ?? {});
      final shareId = share['id']?.toString() ?? '';
      final inviteCode = res['inviteCode']?.toString() ?? '';
      if (shareId.isEmpty || inviteCode.isEmpty) {
        setState(() {
          _saving = false;
          _message = AppStrings.of(context).unableToFinishShareCode;
        });
        return;
      }
      final key = await _crypto.createAndStoreKey(shareId);
      final inviteToken = _crypto.makeInviteToken(inviteCode, key);
      final selectedSections = List<String>.from(_selectedSections);
      final initialPayload = await PersistentFileStore.attachProfileFileBytes(
        ProfileUpdateSyncService().buildPayload(
          profile,
          sections: selectedSections,
        ),
      );
      final encryptedPayload = await _crypto.encryptJson({
        'profileId': profile.id,
        'profileName': profile.fullName,
        'allowedSections': selectedSections,
        'payload': initialPayload,
        'createdAt': DateTime.now().toIso8601String(),
      }, key);
      final staged = await ApiService.createProfileUpdatePackage(
        userId: userId,
        profileId: profile.id,
        profileName: profile.fullName,
        packages: [
          {
            'shareId': shareId,
            'allowedSections': selectedSections,
            'encryptedPayload': encryptedPayload,
          },
        ],
      );
      if (staged['success'] != true) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _message = AppStrings.of(context).unableToFinishShareCode;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _lastInviteCode = inviteToken;
        _message = AppStrings.of(context).shareCodeCreated;
      });
      await _loadShares();
    } else {
      setState(() {
        _saving = false;
        _message =
            (res['error'] ?? AppStrings.of(context).unableToCreateShareLink)
                .toString();
      });
    }
  }

  Future<void> _acceptInvite() async {
    final token = _inviteCtrl.text.trim();

    if (token.isEmpty) {
      _showMessage(AppStrings.of(context).enterShareCodeFirst);
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    final userId = await _store.getString('userId');

    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      _showMessage(AppStrings.of(context).logInAgainBeforeAccepting);
      setState(() => _saving = false);
      return;
    }

    late final ({String inviteCode, String encodedKey}) parsed;
    try {
      parsed = _crypto.parseInviteToken(token);
    } on FormatException catch (e) {
      setState(() {
        _saving = false;
        _message = e.message;
      });
      return;
    }

    final res = await ApiService.acceptProfileShareLink(
      userId: userId,
      inviteCode: parsed.inviteCode,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      final share = Map<String, dynamic>.from(res['share'] as Map? ?? {});
      final shareId = share['id']?.toString() ?? '';
      if (shareId.isNotEmpty) {
        await _crypto.storeKey(shareId, parsed.encodedKey);
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = res['success'] == true
          ? AppStrings.of(context).profileShareAccepted
          : (res['error'] ?? AppStrings.of(context).unableToAcceptShareCode)
              .toString();
    });
  }

  Future<void> _confirmRevokeShare(Map<String, dynamic> share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _VitaLinkDialog(
        title: AppStrings.of(context).revokeAccessQuestion,
        message: AppStrings.of(context).revokeAccessBody(),
        actions: [
          _DialogButton(
            label: AppStrings.of(context).cancel,
            outlined: true,
            onPressed: () => Navigator.pop(context, false),
          ),
          _DialogButton(
            label: AppStrings.of(context).stopSharingUpdates,
            danger: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _revokeShare(share);
    }
  }

  Future<void> _revokeShare(Map<String, dynamic> share) async {
    final shareId = share['id']?.toString() ?? '';

    if (shareId.isEmpty) return;

    setState(() {
      _saving = true;
      _message = null;
    });

    final userId = await _store.getString('userId');

    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      _showMessage(AppStrings.of(context).logInAgainBeforeChangingSharing);
      setState(() => _saving = false);
      return;
    }

    final res = await ApiService.revokeProfileShareLink(
      userId: userId,
      shareId: shareId,
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
      _message = res['success'] == true
          ? AppStrings.of(context).profileAccessRevoked
          : (res['error'] ?? AppStrings.of(context).unableToRevokeAccess)
              .toString();
    });

    if (res['success'] == true) {
      await _crypto.deleteKey(shareId);
      await _loadShares();
    }
  }

  Future<void> _sendInvite(Map<String, dynamic> share) async {
    final inviteCode = share['invite_token']?.toString();

    if (inviteCode == null || inviteCode.isEmpty) {
      _showMessage(AppStrings.of(context).shareHasNoInviteCode);
      return;
    }

    final copiedMessage = AppStrings.of(context).shareCodeCopied;
    await Clipboard.setData(ClipboardData(text: inviteCode));
    _showMessage(copiedMessage);
  }

  Future<void> _sendCurrentProfileUpdate() async {
    if (!_shares.any((share) => share['status']?.toString() == 'accepted')) {
      _showMessage(AppStrings.of(context).shareMustBeAccepted);
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    final profile = await _repo.loadProfile();
    final res = await ProfileUpdateSyncService().publishProfileUpdate(
      profile,
      sections: _selectedSections,
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
      if (res['success'] == true && (res['recipients'] ?? 0) > 0) {
        _message = AppStrings.of(context).currentProfileUpdateSent;
      } else {
        _message = (res['message'] ??
                res['error'] ??
                AppStrings.of(context).noRecipientsReady)
            .toString();
      }
    });

    if (res['success'] == true && (res['recipients'] ?? 0) > 0 && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => _VitaLinkDialog(
          title: AppStrings.of(context).profileSent,
          message: AppStrings.of(context).profileUpdateSentToConnected,
          actions: [
            _DialogButton(
              label: 'OK',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context).profileSharing),
        backgroundColor: const Color(0xFF0E5A88),
      ),
      body: Container(
        color: Colors.black,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              AppStrings.of(context).connectedProfiles,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.of(context).shareProfileExplainer,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 18),
            _InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(context).shareThisProfile,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _field(_emailCtrl, AppStrings.of(context).familyMemberEmail),
                  const SizedBox(height: 10),
                  _field(_phoneCtrl, AppStrings.of(context).familyMemberPhone),
                  const SizedBox(height: 14),
                  _sectionToggle(
                    label: AppStrings.of(context).emergencyProfile,
                    value: _emergency,
                    onChanged: (v) => setState(() => _emergency = v),
                  ),
                  _sectionToggle(
                    label: AppStrings.of(context).medications,
                    value: _medications,
                    onChanged: (v) => setState(() => _medications = v),
                  ),
                  _sectionToggle(
                    label: AppStrings.of(context).doctors,
                    value: _doctors,
                    onChanged: (v) => setState(() => _doctors = v),
                  ),
                  _sectionToggle(
                    label: AppStrings.of(context).insuranceCardsLower,
                    value: _insuranceCards,
                    onChanged: (v) => setState(() => _insuranceCards = v),
                  ),
                  _sectionToggle(
                    label: AppStrings.of(context).insurancePoliciesLower,
                    value: _policies,
                    onChanged: (v) => setState(() => _policies = v),
                  ),
                  _sectionToggle(
                    label: AppStrings.of(context).appointments,
                    value: _appointments,
                    onChanged: (v) => setState(() => _appointments = v),
                  ),
                  const SizedBox(height: 14),
                  _button(
                      AppStrings.of(context).createShareCode, _createShareLink),
                  const SizedBox(height: 10),
                  _button(
                    AppStrings.of(context).sendCurrentProfileUpdate,
                    _sendCurrentProfileUpdate,
                  ),
                ],
              ),
            ),
            _InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(context).whoHasAccess,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingShares)
                    const Center(child: CircularProgressIndicator())
                  else if (_shares.isEmpty)
                    Text(
                      AppStrings.of(context).noActiveProfileShares,
                      style: const TextStyle(color: Colors.white70),
                    )
                  else
                    ..._shares.map(_shareRow),
                ],
              ),
            ),
            _InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(context).acceptSharedProfile,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _field(_inviteCtrl, AppStrings.of(context).shareCodeLower),
                  const SizedBox(height: 14),
                  _button(
                      AppStrings.of(context).acceptShareCode, _acceptInvite),
                ],
              ),
            ),
            if (_lastInviteCode != null && _lastInviteCode!.isNotEmpty)
              _InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(context).shareCodeTitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _lastInviteCode!,
                      style: const TextStyle(
                        color: Color(0xFF78C7E7),
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (_message != null)
              _InfoCard(
                child: Text(
                  _message!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.black,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF26384A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF78C7E7)),
        ),
      ),
    );
  }

  Widget _sectionToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: const Color(0xFF78C7E7),
      title: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _shareRow(Map<String, dynamic> share) {
    final label = _shareLabel(share);
    final status = share['status']?.toString() ?? 'pending';
    final inviteCode = share['invite_token']?.toString();
    final sections = share['allowed_sections'];
    final sectionText = sections is List && sections.isNotEmpty
        ? sections.map((s) => s.toString().replaceAll('_', ' ')).join(', ')
        : AppStrings.of(context).emergencyProfile;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF26384A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$status • $sectionText',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (status == 'pending' &&
              inviteCode != null &&
              inviteCode.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              AppStrings.of(context).codeValue(inviteCode),
              style: const TextStyle(color: Color(0xFF78C7E7)),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.of(context).expiresSixHours,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (status == 'pending')
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF78C7E7),
                    side: const BorderSide(color: Color(0xFF78C7E7)),
                  ),
                  onPressed: _saving ? null : () => _sendInvite(share),
                  child: Text(AppStrings.of(context).copyShareCode),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade200,
                  side: BorderSide(color: Colors.red.shade300),
                ),
                onPressed: _saving ? null : () => _confirmRevokeShare(share),
                child: Text(AppStrings.of(context).revokeAccess),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shareLabel(Map<String, dynamic> share) {
    final email = share['invited_email']?.toString().trim();
    final phone = share['invited_phone']?.toString().trim();

    if (email != null && email.isNotEmpty) return email;
    if (phone != null && phone.isNotEmpty) return phone;
    return AppStrings.of(context).sharedProfileLower;
  }

  Widget _button(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF78C7E7),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: _saving ? null : onPressed,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF78C7E7).withValues(alpha: .35),
        ),
      ),
      child: child,
    );
  }
}

class _VitaLinkDialog extends StatelessWidget {
  const _VitaLinkDialog({
    required this.title,
    required this.message,
    required this.actions,
  });

  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF78C7E7).withValues(alpha: .45),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .45),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool outlined;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red.shade700 : const Color(0xFF78C7E7);

    if (outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF78C7E7),
          side: const BorderSide(color: Color(0xFF78C7E7)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: danger ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
