import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class ProfileSharingScreen extends StatefulWidget {
  const ProfileSharingScreen({super.key});

  @override
  State<ProfileSharingScreen> createState() => _ProfileSharingScreenState();
}

class _ProfileSharingScreenState extends State<ProfileSharingScreen> {
  final SecureStore _store = SecureStore();
  final DataRepository _repo = DataRepository();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _inviteCtrl = TextEditingController();

  bool _emergency = true;
  bool _medications = true;
  bool _doctors = true;
  bool _saving = false;
  bool _loadingShares = true;
  String? _lastInviteCode;
  String? _message;
  List<Map<String, dynamic>> _shares = [];

  @override
  void initState() {
    super.initState();
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

    setState(() {
      _loadingShares = false;
      if (res['success'] == true && res['shares'] is List) {
        _shares = (res['shares'] as List)
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
      }
    });
  }

  Future<void> _createShareLink() async {
    if (_selectedSections.isEmpty) {
      _showMessage('Choose at least one section to share.');
      return;
    }

    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (email.isEmpty && phone.isEmpty) {
      _showMessage('Enter an email or phone number for this share.');
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
      _showMessage('Please log in again before sharing a profile.');
      setState(() => _saving = false);
      return;
    }

    final res = await ApiService.createProfileShareLink(
      userId: userId,
      profileId: profile.id,
      profileName: profile.fullName,
      email: email.isNotEmpty ? email : null,
      phone: phone.isNotEmpty ? phone : null,
      allowedSections: _selectedSections,
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
      if (res['success'] == true) {
        _lastInviteCode = res['inviteCode']?.toString();
        _message = res['status'] == 'accepted'
            ? 'Profile connection is active.'
            : 'Share code created. Give this code to the family member or caregiver.';
      } else {
        _message = (res['error'] ?? 'Unable to create share link.').toString();
      }
    });

    if (res['success'] == true) {
      await _loadShares();
    }
  }

  Future<void> _acceptInvite() async {
    final code = _inviteCtrl.text.trim();

    if (code.isEmpty) {
      _showMessage('Enter the share code first.');
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    final userId = await _store.getString('userId');

    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      _showMessage('Please log in again before accepting a profile share.');
      setState(() => _saving = false);
      return;
    }

    final res = await ApiService.acceptProfileShareLink(
      userId: userId,
      inviteCode: code,
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
      _message = res['success'] == true
          ? 'Profile share accepted. Updates will appear in Profile Updates.'
          : (res['error'] ?? 'Unable to accept share code.').toString();
    });
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
      _showMessage('Please log in again before changing profile sharing.');
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
          ? 'Profile access revoked.'
          : (res['error'] ?? 'Unable to revoke profile access.').toString();
    });

    if (res['success'] == true) {
      await _loadShares();
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
        title: const Text('Profile Sharing'),
        backgroundColor: const Color(0xFF0E5A88),
      ),
      body: Container(
        color: Colors.black,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Connected profiles',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Share selected profile updates with a family member or caregiver. Updates are temporary, encrypted, and removed after connected devices apply them.',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 18),
            _InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Share this profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _field(_emailCtrl, 'Family member email'),
                  const SizedBox(height: 10),
                  _field(_phoneCtrl, 'Phone number optional'),
                  const SizedBox(height: 14),
                  _sectionToggle(
                    label: 'Emergency profile',
                    value: _emergency,
                    onChanged: (v) => setState(() => _emergency = v),
                  ),
                  _sectionToggle(
                    label: 'Medications',
                    value: _medications,
                    onChanged: (v) => setState(() => _medications = v),
                  ),
                  _sectionToggle(
                    label: 'Doctors',
                    value: _doctors,
                    onChanged: (v) => setState(() => _doctors = v),
                  ),
                  const SizedBox(height: 14),
                  _button('Create Share Code', _createShareLink),
                ],
              ),
            ),
            _InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Who has access',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingShares)
                    const Center(child: CircularProgressIndicator())
                  else if (_shares.isEmpty)
                    const Text(
                      'No active profile shares yet.',
                      style: TextStyle(color: Colors.white70),
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
                  const Text(
                    'Accept a shared profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _field(_inviteCtrl, 'Share code'),
                  const SizedBox(height: 14),
                  _button('Accept Share Code', _acceptInvite),
                ],
              ),
            ),
            if (_lastInviteCode != null && _lastInviteCode!.isNotEmpty)
              _InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Share Code',
                      style: TextStyle(
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
    final email = share['invited_email']?.toString().trim();
    final phone = share['invited_phone']?.toString().trim();
    final status = share['status']?.toString() ?? 'pending';
    final inviteCode = share['invite_code']?.toString();
    final sections = share['allowed_sections'];
    final sectionText = sections is List && sections.isNotEmpty
        ? sections.map((s) => s.toString().replaceAll('_', ' ')).join(', ')
        : 'Emergency profile';

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
            email?.isNotEmpty == true
                ? email!
                : phone?.isNotEmpty == true
                    ? phone!
                    : 'Shared profile',
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
              'Code: $inviteCode',
              style: const TextStyle(color: Color(0xFF78C7E7)),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade200,
              side: BorderSide(color: Colors.red.shade300),
            ),
            onPressed: _saving ? null : () => _revokeShare(share),
            child: const Text('Revoke Access'),
          ),
        ],
      ),
    );
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
