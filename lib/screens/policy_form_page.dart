import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class Policy {
  final String company;
  final String plan;

  Policy({required this.company, required this.plan});
}

class PolicyFormPage extends StatefulWidget {
  final Policy? policy;

  const PolicyFormPage({super.key, this.policy});

  @override
  State<PolicyFormPage> createState() => _PolicyFormPageState();
}

class _PolicyFormPageState extends State<PolicyFormPage> {
  late TextEditingController companyController;
  late TextEditingController planController;

  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    companyController =
        TextEditingController(text: widget.policy?.company ?? '');
    planController = TextEditingController(text: widget.policy?.plan ?? '');

    _repo = DataRepository(SecureStore());
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _repo.loadProfile();
    setState(() {
      _p = profile;
      _loading = false;
    });
  }

  void _save() {
    final newPolicy = Policy(
      company: companyController.text.trim(),
      plan: planController.text.trim(),
    );
    Navigator.pop(context, newPolicy);
  }

  void _cancel() {
    Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final titleBase = widget.policy == null ? "New Policy" : "Edit Policy";
    final title = _p?.fullName.isNotEmpty == true
        ? "$titleBase – ${_p!.fullName}"
        : titleBase;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Column(
              children: [
                TextField(
                  controller: companyController,
                  decoration: const InputDecoration(labelText: "Company"),
                ),
                const Divider(height: 1),
              ],
            ),
            Column(
              children: [
                TextField(
                  controller: planController,
                  decoration: const InputDecoration(labelText: "Plan"),
                ),
                const Divider(height: 1),
              ],
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
