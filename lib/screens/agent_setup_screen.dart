import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import '../services/secure_store.dart';
import '../utils/phone_formatter.dart';

class AgentSetupScreen extends StatefulWidget {
  const AgentSetupScreen({super.key});

  @override
  State<AgentSetupScreen> createState() => _AgentSetupScreenState();
}

class _AgentSetupScreenState extends State<AgentSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _agencyCtrl = TextEditingController();

  final _agencyPhoneCtrl = TextEditingController(); // 🔥 NEW

  // 🔥 ADDRESS FIELDS (REPLACES SINGLE ADDRESS)
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  final _licenseCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = SecureStore();
    _nameCtrl.text = await store.getString('agentName') ?? '';
    _phoneCtrl.text = await store.getString('agentPhone') ?? '';
    _agencyCtrl.text = await store.getString('agencyName') ?? '';
    _agencyPhoneCtrl.text = await store.getString('agencyPhone') ?? '';

    // 🔥 LOAD ADDRESS FIELDS
    _addressCtrl.text = await store.getString('agencyAddress') ?? '';
    _cityCtrl.text = await store.getString('agencyCity') ?? '';
    _stateCtrl.text = await store.getString('agencyState') ?? '';
    _zipCtrl.text = await store.getString('agencyZip') ?? '';

    _licenseCtrl.text = await store.getString('agentId') ?? '';
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final store = SecureStore();
    await store.setBool('agentSetupDone', true);
    await store.setString('role', 'agent');

    await store.setString('agentName', _nameCtrl.text.trim());
    await store.setString('agentPhone', _phoneCtrl.text.trim());

    await store.setString('agencyName', _agencyCtrl.text.trim());
    await store.setString('agencyPhone', _agencyPhoneCtrl.text.trim());

    // 🔥 SAVE ADDRESS FIELDS
    await store.setString('agencyAddress', _addressCtrl.text.trim());
    await store.setString('agencyCity', _cityCtrl.text.trim());
    await store.setString('agencyState', _stateCtrl.text.trim());
    await store.setString('agencyZip', _zipCtrl.text.trim());

    await store.setString('agentId', _licenseCtrl.text.trim());

    if (_passwordCtrl.text.isNotEmpty) {
      await store.setString('agentPassword', _passwordCtrl.text.trim());
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/agent_menu');
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).agentProfile)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).fullName),
                  validator: (v) => v == null || v.isEmpty
                      ? AppStrings.of(context).enterYourName
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneNumberFormatter()],
                  decoration:
                      InputDecoration(labelText: AppStrings.of(context).phone),
                  validator: (v) => v == null || v.isEmpty
                      ? AppStrings.of(context).enterYourPhone
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _agencyCtrl,
                  decoration:
                      InputDecoration(labelText: AppStrings.of(context).agency),
                ),
                const SizedBox(height: 12),

                // 🔥 NEW AGENCY PHONE
                TextFormField(
                  controller: _agencyPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneNumberFormatter()],
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).agencyPhoneNumber),
                ),
                const SizedBox(height: 12),

                // 🔥 ADDRESS BLOCK
                TextFormField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).streetAddress),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _cityCtrl,
                  decoration:
                      InputDecoration(labelText: AppStrings.of(context).city),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stateCtrl,
                        decoration: InputDecoration(
                            labelText: AppStrings.of(context).state),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _zipCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "ZIP"),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                TextFormField(
                  controller: _licenseCtrl,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).npnLicense),
                  validator: (v) => v == null || v.isEmpty
                      ? AppStrings.of(context).enterYourNpn
                      : null,
                ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),

                Text(
                  AppStrings.of(context).updatePasswordOptional,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).newPassword),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: AppStrings.of(context).confirmPassword),
                  validator: (v) {
                    if (_passwordCtrl.text.isNotEmpty &&
                        v != _passwordCtrl.text) {
                      return AppStrings.of(context).passwordsDontMatchCurly;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _save,
                        child: Text(AppStrings.of(context).saveProfile),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
