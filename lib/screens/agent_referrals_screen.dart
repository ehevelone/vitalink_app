import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/secure_store.dart';

class AgentReferralsScreen extends StatefulWidget {
  const AgentReferralsScreen({super.key});

  @override
  State<AgentReferralsScreen> createState() => _AgentReferralsScreenState();
}

class _AgentReferralsScreenState extends State<AgentReferralsScreen> {
  static const _statuses = [
    'Introduction Sent',
    'Referral Link Opened',
    'Contact Preference Submitted',
    'Agent Contacted',
    'Appointment Scheduled',
    'Client Added',
    'Closed',
  ];

  final _store = SecureStore();
  List<Map<String, dynamic>> _referrals = [];
  Map<String, dynamic> _metrics = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReferrals();
  }

  Future<int?> _agentId() async {
    final raw = await _store.getString('agentId');
    return int.tryParse(raw ?? '');
  }

  Future<void> _loadReferrals() async {
    final agentId = await _agentId();
    if (agentId == null) {
      setState(() {
        _loading = false;
        _error = 'Please log in again before viewing referrals.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await ApiService.getAgentReferrals(agentId: agentId);
    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _referrals = (res['referrals'] as List? ?? [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        _metrics = Map<String, dynamic>.from(res['metrics'] as Map? ?? {});
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['error']?.toString() ?? 'Failed to load referrals.';
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> referral, String status) async {
    final agentId = await _agentId();
    final referralId = referral['id']?.toString();
    if (agentId == null || referralId == null || referralId.isEmpty) return;

    final res = await ApiService.updateAgentReferralStatus(
      agentId: agentId,
      referralId: referralId,
      status: status,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      await _loadReferrals();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['error']?.toString() ?? 'Update failed.')),
      );
    }
  }

  Future<void> _confirmDeleteReferral(Map<String, dynamic> referral) async {
    final referralName = referral['referral_name']?.toString() ?? 'this referral';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: Colors.lightBlueAccent.withValues(alpha: .35),
            ),
          ),
          title: const Text(
            'Delete Referral?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Remove $referralName from your referral list? This only removes the referral record from your agent screen.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.lightBlueAccent),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteReferral(referral);
    }
  }

  Future<void> _deleteReferral(Map<String, dynamic> referral) async {
    final agentId = await _agentId();
    final referralId = referral['id']?.toString();
    if (agentId == null || referralId == null || referralId.isEmpty) return;

    final res = await ApiService.deleteAgentReferral(
      agentId: agentId,
      referralId: referralId,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referral deleted.')),
      );
      await _loadReferrals();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['error']?.toString() ?? 'Delete failed.')),
      );
    }
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
        actions: [
          IconButton(
            onPressed: _loadReferrals,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    _buildMetrics(),
                    const SizedBox(height: 16),
                    if (_referrals.isEmpty)
                      const Text(
                        'No referrals yet.',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      )
                    else
                      ..._referrals.map(_referralCard),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildMetrics() {
    final total = _metrics['total'] ?? 0;
    final contact = _percent(_metrics['contactRate']);
    final appointment = _percent(_metrics['appointmentRate']);
    final conversion = _percent(_metrics['conversionRate']);
    final pending = _metrics['pending'] ?? 0;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _metric('Total', '$total'),
        _metric('Pending', '$pending'),
        _metric('Contact', contact),
        _metric('Appointments', appointment),
        _metric('Conversion', conversion),
      ],
    );
  }

  String _percent(dynamic value) {
    final number = value is num ? value.toDouble() : 0.0;
    return '${(number * 100).round()}%';
  }

  String _formatDateTime(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return '';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final local = parsed.toLocal();
    final hour = local.hour == 0
        ? 12
        : local.hour > 12
            ? local.hour - 12
            : local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';

    return '${local.month}/${local.day}/${local.year} $hour:$minute $ampm';
  }

  Widget _metric(String label, String value) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.lightBlueAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _referralCard(Map<String, dynamic> referral) {
    final currentStatus = _statuses.contains(referral['status'])
        ? referral['status'].toString()
        : 'Introduction Sent';
    final contactedAt = _formatDateTime(referral['agent_first_contacted_at']);

    return Card(
      color: const Color(0xFF111827),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.lightBlueAccent.withValues(alpha: .3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              referral['referral_name']?.toString() ?? 'Referral',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _line('Phone', referral['referral_phone']),
            _line('Email', referral['referral_email']),
            _line('Relationship', referral['relationship']),
            _line('Reason', referral['reason']),
            _line('Preferred Contact', referral['contact_preference']),
            _line('Referred By', referral['referring_client']),
            _line('Received', _formatDateTime(referral['submitted_at'])),
            _line('Link Opened', _formatDateTime(referral['link_opened_at'])),
            _line(
              'Preference Submitted',
              _formatDateTime(referral['contact_preference_submitted_at']),
            ),
            _line('Contacted', contactedAt),
            if ((referral['notes']?.toString() ?? '').isNotEmpty)
              _line('Notes', referral['notes']),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: currentStatus,
              dropdownColor: const Color(0xFF111827),
              decoration: InputDecoration(
                labelText: 'Status',
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.lightBlueAccent),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              items: _statuses
                  .map((status) => DropdownMenuItem(
                        value: status,
                        child: Text(status),
                      ))
                  .toList(),
              onChanged: (status) {
                if (status != null) _updateStatus(referral, status);
              },
            ),
            if (currentStatus != 'Agent Contacted' && contactedAt.isEmpty) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _updateStatus(referral, 'Agent Contacted'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.lightBlueAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.phone_callback),
                label: const Text(
                  'Mark Contacted',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _confirmDeleteReferral(referral),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text(
                'Delete Referral',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $text',
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      ),
    );
  }
}
