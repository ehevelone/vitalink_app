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
        : 'New';

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
