import 'package:flutter/material.dart';
import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import '../utils/phone_formatter.dart';

class InsurancePolicyForm extends StatefulWidget {
  final Insurance policy;
  final List<Insurance> allPolicies;

  const InsurancePolicyForm({
    super.key,
    required this.policy,
    required this.allPolicies,
  });

  @override
  State<InsurancePolicyForm> createState() => _InsurancePolicyFormState();
}

class _InsurancePolicyFormState extends State<InsurancePolicyForm> {
  late TextEditingController carrier;
  late TextEditingController policyNo;
  late TextEditingController groupNo;
  late TextEditingController memberId;
  late TextEditingController phone;
  late TextEditingController policyType;

  // 🔥 NEW
  late TextEditingController insuredName;
  late TextEditingController beneficiary;

  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    carrier = TextEditingController(text: widget.policy.carrier);
    policyNo = TextEditingController(text: widget.policy.policy);
    groupNo = TextEditingController(text: widget.policy.group);
    memberId = TextEditingController(text: widget.policy.memberId);
    phone = TextEditingController(text: widget.policy.phone);
    policyType = TextEditingController(text: widget.policy.policyType);

    // 🔥 NEW
    insuredName = TextEditingController(text: widget.policy.insuredName);
    beneficiary = TextEditingController(text: widget.policy.beneficiary);

    _repo = DataRepository(SecureStore());
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final p = await _repo.loadProfile();
    setState(() {
      _p = p;
      _loading = false;
    });
  }

  @override
  void dispose() {
    carrier.dispose();
    policyNo.dispose();
    groupNo.dispose();
    memberId.dispose();
    phone.dispose();
    policyType.dispose();

    // 🔥 NEW
    insuredName.dispose();
    beneficiary.dispose();

    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _save() {
    final updated = Insurance(
      carrier: carrier.text.trim(),
      policy: policyNo.text.trim(),
      group: groupNo.text.trim(),
      memberId: memberId.text.trim(),
      phone: phone.text.trim(),
      policyType: policyType.text.trim(),

      // 🔥 NEW FIELDS
      insuredName: insuredName.text.trim(),
      beneficiary: beneficiary.text.trim(),

      // KEEP EXISTING
      benefits: widget.policy.benefits,
      decPagePaths: widget.policy.decPagePaths,
      cards: widget.policy.cards,
    );

    final duplicate = widget.allPolicies.where((i) =>
        i != widget.policy &&
        i.carrier.trim().toLowerCase() ==
            updated.carrier.trim().toLowerCase() &&
        i.policy.trim() == updated.policy.trim());

    if (duplicate.isNotEmpty) {
      final idx = widget.allPolicies.indexOf(duplicate.first);
      widget.allPolicies[idx] = updated;
      _showSnack("Merged into existing policy");
      Navigator.pop(context, updated);
      return;
    }

    _showSnack(
      widget.policy.carrier.isEmpty && widget.policy.policy.isEmpty
          ? "Created new policy"
          : "Policy updated",
    );

    Navigator.pop(context, updated);
  }

  void _cancel() => Navigator.pop(context, null);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profileName =
        (_p != null && _p!.fullName.isNotEmpty ? " – ${_p!.fullName}" : "");

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.policy.carrier.isEmpty
              ? "New Insurance Policy$profileName"
              : "Edit Insurance Policy$profileName",
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: "Save",
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: carrier,
              decoration: const InputDecoration(labelText: "Carrier"),
            ),
            TextField(
              controller: policyNo,
              decoration: const InputDecoration(labelText: "Policy #"),
            ),
            TextField(
              controller: groupNo,
              decoration: const InputDecoration(labelText: "Group #"),
            ),
            TextField(
              controller: memberId,
              decoration: const InputDecoration(labelText: "Member ID"),
            ),

            // 🔥 NEW FIELDS (THIS FIXES YOUR ISSUE)
            TextField(
              controller: insuredName,
              decoration:
                  const InputDecoration(labelText: "Insured Name"),
            ),
            TextField(
              controller: beneficiary,
              decoration:
                  const InputDecoration(labelText: "Beneficiary"),
            ),

            TextField(
              controller: phone,
              decoration: const InputDecoration(labelText: "Phone"),
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneNumberFormatter()],
            ),
            TextField(
              controller: policyType,
              decoration: const InputDecoration(labelText: "Policy Type"),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _cancel,
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _save,
                  child: const Text("Save"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}