import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
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
    'Friend',
    'Coworker',
    'Neighbor',
    'Relative',
    'Other',
  ];

  final _store = SecureStore();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _mode = 'home';
  String _relationship = 'Friend';
  String _source = 'send_introduction';
  bool _saving = false;
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
      });
    }
  }

  String _introductionMessage({
    required String name,
    required String referralLink,
  }) {
    final agent = (_agentName == null || _agentName!.isEmpty)
        ? AppStrings.of(context).myInsuranceAgent
        : AppStrings.of(context).myAgentNamed(_agentName!);

    return AppStrings.of(context)
        .referralIntroMessage(name, agent, referralLink);
  }

  void _openForm({
    String relationship = 'Friend',
  }) {
    _nameCtrl.clear();
    _phoneCtrl.clear();
    setState(() {
      _source = 'send_introduction';
      _relationship = relationship;
      _mode = 'form';
    });
  }

  Future<void> _submitReferral() async {
    final userId = await _store.getString('userId');
    if (!mounted) return;
    if (userId == null || userId.isEmpty) {
      _showMessage(AppStrings.of(context).logInBeforeReferral);
      return;
    }

    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty) {
      _showMessage(AppStrings.of(context).enterReferralNameFirst);
      return;
    }

    if (phone.isEmpty) {
      _showMessage(AppStrings.of(context).enterPhoneForIntro);
      return;
    }

    setState(() => _saving = true);

    final res = await ApiService.submitAgentReferral(
      userId: userId,
      referralName: name,
      phone: phone,
      relationship: _relationship,
      source: _source,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (res['success'] == true) {
      final referralLink = res['referralLink']?.toString() ?? '';
      final message = _introductionMessage(
        name: name,
        referralLink: referralLink,
      );

      setState(() => _mode = 'home');

      final uri = Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {'body': message},
      );
      try {
        final opened = await launchUrl(uri);
        if (!mounted) return;
        _showMessage(
          opened
              ? AppStrings.of(context).introTextOpened
              : AppStrings.of(context).couldNotOpenText,
        );
      } catch (_) {
        if (!mounted) return;
        _showMessage(AppStrings.of(context).couldNotOpenText);
      }
    } else {
      _showMessage(
          res['error']?.toString() ?? AppStrings.of(context).referralFailed);
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
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: Text(
          AppStrings.of(context).referralCenter,
          style: const TextStyle(fontWeight: FontWeight.bold),
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
    return _buildHome();
  }

  Widget _buildHome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          AppStrings.of(context).referralCenter,
          AppStrings.of(context).referralCenterBody,
        ),
        _optionCard(
          icon: Icons.sms,
          title: AppStrings.of(context).sendIntroduction,
          subtitle: AppStrings.of(context).createTextToReview,
          onTap: _openForm,
        ),
      ],
    );
  }

  Widget _buildReferralForm({String? title, String? prompt}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          title ?? AppStrings.of(context).sendIntroduction,
          prompt ?? AppStrings.of(context).createIntroOutsideHousehold,
        ),
        _field(_nameCtrl, AppStrings.of(context).name),
        _field(_phoneCtrl, AppStrings.of(context).phoneNumber,
            keyboardType: TextInputType.phone),
        _dropdown(
          label: AppStrings.of(context).relationshipOptional,
          value: _relationship,
          options: _relationships.contains(_relationship)
              ? _relationships
              : [..._relationships, _relationship],
          onChanged: (v) => setState(() => _relationship = v),
        ),
        const SizedBox(height: 12),
        _primaryButton(AppStrings.of(context).generateIntroText,
            _saving ? null : _submitReferral),
        _textButton(
            AppStrings.of(context).back, () => setState(() => _mode = 'home')),
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
        side:
            BorderSide(color: Colors.lightBlue.shade200.withValues(alpha: .35)),
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
            borderSide:
                const BorderSide(color: Colors.lightBlueAccent, width: 2),
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
                  child: Text(AppStrings.of(context).relationshipLabel(option)),
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
