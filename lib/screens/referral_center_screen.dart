import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/secure_store.dart';

class ReferralCenterScreen extends StatefulWidget {
  const ReferralCenterScreen({super.key});

  @override
  State<ReferralCenterScreen> createState() => _ReferralCenterScreenState();
}

class _ReferralCenterScreenState extends State<ReferralCenterScreen> {
  static const _relationships = [
    'Spouse',
    'Parent',
    'Child',
    'Grandparent',
    'Friend',
    'Coworker',
    'Neighbor',
    'Caregiver',
    'Other',
  ];

  static const _familyRelationships = [
    'Spouse',
    'Parent',
    'Grandparent',
    'Adult Child',
    'Caregiver',
  ];

  static const _reasons = [
    'Turning 65',
    'Medicare Questions',
    'Insurance Review',
    'Multiple Medications',
    'Caregiver Needs',
    'Recently Retired',
    'Wants Better Organization',
    'Emergency Preparedness',
    'Family Member Concern',
    'Other',
  ];

  final _store = SecureStore();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _introPhoneCtrl = TextEditingController();
  final _introMessageCtrl = TextEditingController();

  String _mode = 'home';
  String _relationship = 'Friend';
  String _reason = 'Insurance Review';
  String _source = 'recommend_my_agent';
  List<Map<String, dynamic>> _referrals = [];
  bool _saving = false;
  bool _loadingReferrals = false;
  String? _agentName;

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    _introPhoneCtrl.dispose();
    _introMessageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAgent() async {
    final email = await _store.getString('userEmail');
    if (email == null || email.isEmpty) return;

    final res = await ApiService.getUserAgent(email);
    if (!mounted) return;

    if (res['success'] == true && res['agent'] is Map) {
      final agent = Map<String, dynamic>.from(res['agent'] as Map);
      setState(() {
        _agentName = agent['name']?.toString();
        _introMessageCtrl.text = _defaultIntroMessage();
      });
    } else {
      _introMessageCtrl.text = _defaultIntroMessage();
    }
  }

  String _defaultIntroMessage() {
    final agent = (_agentName == null || _agentName!.isEmpty)
        ? 'my insurance agent'
        : 'my insurance agent, $_agentName';

    return "Hi! I've been using VitaLink to keep my medications, doctors, "
        "insurance cards, and emergency information organized. $agent helped "
        "me get set up. I thought you might find it helpful as well. Would it "
        "be okay if I have them reach out to you?";
  }

  void _openForm({
    required String source,
    String relationship = 'Friend',
    String reason = 'Insurance Review',
  }) {
    _nameCtrl.clear();
    _phoneCtrl.clear();
    _emailCtrl.clear();
    _notesCtrl.clear();
    setState(() {
      _source = source;
      _relationship = relationship;
      _reason = reason;
      _mode = 'form';
    });
  }

  Future<void> _submitReferral() async {
    final userId = await _store.getString('userId');
    if (userId == null || userId.isEmpty) {
      _showMessage('Please log in again before submitting a referral.');
      return;
    }

    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.isEmpty) {
      _showMessage('Enter the referral name first.');
      return;
    }

    if (phone.isEmpty && email.isEmpty) {
      _showMessage('Enter a phone number or email for the referral.');
      return;
    }

    setState(() => _saving = true);

    final res = await ApiService.submitAgentReferral(
      userId: userId,
      referralName: name,
      phone: phone.isEmpty ? null : phone,
      email: email.isEmpty ? null : email,
      relationship: _relationship,
      reason: _reason,
      notes: _notesCtrl.text.trim(),
      source: _source,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (res['success'] == true) {
      final referralLink = res['referralLink']?.toString() ?? '';
      final agentName = res['agentName']?.toString() ?? _agentName ?? 'my insurance agent';
      final referringClient = res['referringClient']?.toString() ?? 'I';
      final message = referralLink.isEmpty
          ? _defaultIntroMessage()
          : "Hi $name,\n\n"
              "$referringClient uses VitaLink to keep medications, doctors, "
              "insurance cards, and emergency information organized.\n\n"
              "$agentName helped with setup, and I thought you might find it "
              "helpful too.\n\n"
              "You can learn more and choose how you'd like to be contacted here:\n"
              "$referralLink";

      setState(() => _mode = 'home');
      _showMessage('Referral link created. Send the text to complete the introduction.');

      if (phone.isNotEmpty) {
        final uri = Uri(
          scheme: 'sms',
          path: phone,
          queryParameters: {'body': message},
        );
        await launchUrl(uri);
      }
    } else {
      _showMessage(res['error']?.toString() ?? 'Referral failed.');
    }
  }

  Future<void> _sendIntroText() async {
    final phone = _introPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      _showMessage('Enter the phone number first.');
      return;
    }

    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': _introMessageCtrl.text.trim()},
    );

    if (!await launchUrl(uri)) {
      _showMessage('Could not open text message composer.');
    }
  }

  Future<void> _loadMyReferrals() async {
    final userId = await _store.getString('userId');
    if (userId == null || userId.isEmpty) return;

    setState(() {
      _mode = 'referrals';
      _loadingReferrals = true;
    });

    final res = await ApiService.getMyReferrals(userId: userId);
    if (!mounted) return;

    setState(() {
      _loadingReferrals = false;
      _referrals = (res['referrals'] as List? ?? [])
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: const Text(
          'Referral Center',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == 'form') return _buildReferralForm();
    if (_mode == 'intro') return _buildIntro();
    if (_mode == 'family') return _buildFamily();
    if (_mode == 'caregiver') {
      return _buildReferralForm(
        title: 'Invite a Caregiver',
        prompt:
            'Caregivers often help manage appointments, medications, insurance information, and emergency contacts.',
      );
    }
    if (_mode == 'referrals') return _buildMyReferrals();
    return _buildHome();
  }

  Widget _buildHome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          'Warm Introductions',
          'Help friends and family connect with the agent who helped you get organized.',
        ),
        _optionCard(
          icon: Icons.person_add_alt_1,
          title: 'Recommend My Agent',
          subtitle: 'Send a warm referral directly to your agent.',
          onTap: () => _openForm(source: 'recommend_my_agent'),
        ),
        _optionCard(
          icon: Icons.sms,
          title: 'Introduce My Agent',
          subtitle: 'Send an editable text message from your phone.',
          onTap: () => setState(() => _mode = 'intro'),
        ),
        _optionCard(
          icon: Icons.family_restroom,
          title: 'Help Protect a Family Member',
          subtitle: 'Start with the person you are concerned about.',
          onTap: () => setState(() => _mode = 'family'),
        ),
        _optionCard(
          icon: Icons.volunteer_activism,
          title: 'Invite a Caregiver',
          subtitle: 'Connect a caregiver with your agent for help.',
          onTap: () {
            _openForm(
              source: 'caregiver',
              relationship: 'Caregiver',
              reason: 'Caregiver Needs',
            );
            setState(() => _mode = 'caregiver');
          },
        ),
        _optionCard(
          icon: Icons.list_alt,
          title: 'My Referrals',
          subtitle: 'See referrals you have already submitted.',
          onTap: _loadMyReferrals,
        ),
      ],
    );
  }

  Widget _buildReferralForm({String? title, String? prompt}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(title ?? 'Recommend My Agent', prompt ?? 'Send a warm referral to your connected insurance agent.'),
        _field(_nameCtrl, 'Referral Name'),
        _field(_phoneCtrl, 'Phone Number', keyboardType: TextInputType.phone),
        _field(_emailCtrl, 'Email Address', keyboardType: TextInputType.emailAddress),
        _dropdown(
          label: 'Relationship',
          value: _relationship,
          options: _relationships.contains(_relationship)
              ? _relationships
              : [..._relationships, _relationship],
          onChanged: (v) => setState(() => _relationship = v),
        ),
        _dropdown(
          label: 'Reason For Referral',
          value: _reason,
          options: _reasons,
          onChanged: (v) => setState(() => _reason = v),
        ),
        _field(_notesCtrl, 'Optional Notes', maxLines: 4),
        const SizedBox(height: 12),
        _primaryButton('Submit Referral', _saving ? null : _submitReferral),
        _textButton('Back', () => setState(() => _mode = 'home')),
      ],
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          'Introduce My Agent',
          'Edit the message, then send it from your phone.',
        ),
        _field(_introPhoneCtrl, 'Recipient Phone Number',
            keyboardType: TextInputType.phone),
        _field(_introMessageCtrl, 'Message', maxLines: 8),
        const SizedBox(height: 12),
        _primaryButton('Open Text Message', _sendIntroText),
        _textButton('Back', () => setState(() => _mode = 'home')),
      ],
    );
  }

  Widget _buildFamily() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          'Help Protect a Family Member',
          'Does someone you care about keep medications, insurance cards, or medical information in multiple places?',
        ),
        ..._familyRelationships.map((relationship) {
          return _optionCard(
            icon: Icons.favorite,
            title: relationship,
            subtitle: 'Start a referral for this family member.',
            onTap: () => _openForm(
              source: 'family_member',
              relationship: relationship,
              reason: 'Family Member Concern',
            ),
          );
        }),
        _textButton('Back', () => setState(() => _mode = 'home')),
      ],
    );
  }

  Widget _buildMyReferrals() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header('My Referrals', 'Referral status shown without agent notes.'),
        if (_loadingReferrals)
          const Center(child: CircularProgressIndicator())
        else if (_referrals.isEmpty)
          const Text(
            'No referrals submitted yet.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          )
        else
          ..._referrals.map(_referralTile),
        _textButton('Back', () => setState(() => _mode = 'home')),
      ],
    );
  }

  Widget _header(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _optionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: const Color(0xFF111827),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.lightBlue.shade200.withValues(alpha: .35)),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.lightBlueAccent, size: 30),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: onTap,
      ),
    );
  }

  Widget _referralTile(Map<String, dynamic> referral) {
    return Card(
      color: const Color(0xFF111827),
      child: ListTile(
        title: Text(
          referral['referral_name']?.toString() ?? 'Referral',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${referral['relationship'] ?? 'Referral'}\nStatus: ${referral['status'] ?? 'Received'}',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.black,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.lightBlueAccent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        dropdownColor: const Color(0xFF111827),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.black,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.lightBlueAccent),
          ),
        ),
        style: const TextStyle(color: Colors.white),
        items: options
            .map((option) => DropdownMenuItem(
                  value: option,
                  child: Text(option),
                ))
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.lightBlueAccent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _textButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(color: Colors.lightBlueAccent)),
    );
  }
}
