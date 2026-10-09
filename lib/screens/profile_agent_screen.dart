// lib/screens/profile_agent_screen.dart
import 'dart:convert';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../services/secure_store.dart';
import '../services/api_service.dart';
import '../widgets/password_rules.dart';
import '../utils/phone_formatter.dart';

class ProfileAgentScreen extends StatefulWidget {
  const ProfileAgentScreen({super.key});

  @override
  State<ProfileAgentScreen> createState() => _ProfileAgentScreenState();
}

class _ProfileAgentScreenState extends State<ProfileAgentScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _agencyNameCtrl = TextEditingController();
  final _agencyAddressCtrl = TextEditingController();
  final _calendlyUrlCtrl = TextEditingController();
  final _agencyPhoneCtrl = TextEditingController(); // 🔥 ADDED

  // 🔥 ADDRESS FIELDS ADDED
  final _agencyCityCtrl = TextEditingController();
  final _agencyStateCtrl = TextEditingController();
  final _agencyZipCtrl = TextEditingController();

  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _scanningCard = false;
  bool _autoScanHandled = false;
  bool _showPassword = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    _loadLocalProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _agencyNameCtrl.dispose();
    _agencyAddressCtrl.dispose();
    _agencyPhoneCtrl.dispose();
    _calendlyUrlCtrl.dispose();
    _agencyCityCtrl.dispose();
    _agencyStateCtrl.dispose();
    _agencyZipCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocalProfile() async {
    final store = SecureStore();

    _nameCtrl.text = await store.getString('agentName') ?? '';
    _emailCtrl.text = await store.getString('agentEmail') ?? '';
    _phoneCtrl.text = await store.getString('agentPhone') ?? '';
    _agencyNameCtrl.text = await store.getString('agencyName') ??
        await store.getString('agentAgency') ??
        '';
    _agencyAddressCtrl.text = await store.getString('agencyAddress') ?? '';

    _agencyPhoneCtrl.text = await store.getString('agencyPhone') ?? '';
    _calendlyUrlCtrl.text = await store.getString('agentCalendlyUrl') ?? '';

    // 🔥 LOAD NEW ADDRESS FIELDS
    _agencyCityCtrl.text = await store.getString('agencyCity') ?? '';
    _agencyStateCtrl.text = await store.getString('agencyState') ?? '';
    _agencyZipCtrl.text = await store.getString('agencyZip') ?? '';

    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    final profileRes = await ApiService.getAgentProfile(email: email);
    if (!mounted || profileRes['success'] != true) return;

    final agent = profileRes['agent'];
    if (agent is! Map) return;

    _nameCtrl.text = agent['name']?.toString() ?? _nameCtrl.text;
    _phoneCtrl.text = agent['phone']?.toString() ?? _phoneCtrl.text;
    _agencyNameCtrl.text =
        agent['agency_name']?.toString() ?? _agencyNameCtrl.text;
    _agencyAddressCtrl.text = agent['agency_street']?.toString() ??
        agent['agency_address']?.toString() ??
        _agencyAddressCtrl.text;
    _agencyPhoneCtrl.text =
        agent['agency_phone']?.toString() ?? _agencyPhoneCtrl.text;
    _calendlyUrlCtrl.text =
        agent['calendly_url']?.toString() ?? _calendlyUrlCtrl.text;
    _agencyCityCtrl.text =
        agent['agency_city']?.toString() ?? _agencyCityCtrl.text;
    _agencyStateCtrl.text =
        agent['agency_state']?.toString() ?? _agencyStateCtrl.text;
    _agencyZipCtrl.text =
        agent['agency_zip']?.toString() ?? _agencyZipCtrl.text;

    setState(() {});

    if (!_autoScanHandled) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['autoScan'] == true) {
        _autoScanHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scanBusinessCard();
        });
      }
    }
  }

  String _value(Map data, String key) => data[key]?.toString().trim() ?? '';

  Future<String?> _businessCardPreviewBase64(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return base64Encode(bytes);

    final resized =
        decoded.width > 1000 ? img.copyResize(decoded, width: 1000) : decoded;
    return base64Encode(img.encodeJpg(resized, quality: 78));
  }

  Future<void> _scanBusinessCard() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).agentEmailRequiredScan)),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }

      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
            content: Text(AppStrings.of(context).cameraPermissionNotGranted)),
      );
      return;
    }

    setState(() => _scanningCard = true);

    try {
      await Future.delayed(const Duration(milliseconds: 200));

      final images = await CunningDocumentScanner.getPictures();
      if (images == null || images.isEmpty) return;
      final cardImageBase64 = await _businessCardPreviewBase64(images.first);

      final res = await ApiService.parseAgentBusinessCard(
        image: File(images.first),
        agentEmail: _emailCtrl.text.trim(),
        cardImageBase64: cardImageBase64,
      );

      if (!mounted) return;

      if (res['success'] != true) {
        messenger.showSnackBar(
          SnackBar(
              content: Text(res['error'] ??
                  AppStrings.of(context).businessCardScanFailed)),
        );
        return;
      }

      final data = res['data'];
      if (data is! Map) {
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).noBusinessCardDetails)),
        );
        return;
      }

      await _reviewBusinessCardFields(data);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(AppStrings.of(context).businessCardScanFailedError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _scanningCard = false);
    }
  }

  Future<void> _reviewBusinessCardFields(Map data) async {
    final parsedEmail = _value(data, 'email');
    final notes = <String>[
      if (parsedEmail.isNotEmpty && parsedEmail != _emailCtrl.text.trim())
        AppStrings.of(context).cardEmailFound(parsedEmail),
      if (data['hasLogo'] == true) AppStrings.of(context).logoDetected(),
      if (data['hasHeadshot'] == true)
        AppStrings.of(context).headshotDetected(),
    ];

    final apply = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppStrings.of(context).reviewBusinessCard,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _previewLine(AppStrings.of(context).name, _value(data, 'name')),
              _previewLine(AppStrings.of(context).phone, _value(data, 'phone')),
              _previewLine(
                  AppStrings.of(context).agency, _value(data, 'agencyName')),
              _previewLine(
                  AppStrings.of(context).addressLabel, _value(data, 'address')),
              _previewLine(AppStrings.of(context).city, _value(data, 'city')),
              _previewLine(AppStrings.of(context).state, _value(data, 'state')),
              _previewLine("ZIP", _value(data, 'zip')),
              _previewLine("Calendly", _value(data, 'calendlyUrl')),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                ...notes.map(
                  (note) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(note,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).apply),
          ),
        ],
      ),
    );

    if (apply != true) return;

    setState(() {
      final name = _value(data, 'name');
      final phone = _value(data, 'phone');
      final agency = _value(data, 'agencyName');
      final address = _value(data, 'address');
      final city = _value(data, 'city');
      final state = _value(data, 'state');
      final zip = _value(data, 'zip');
      final calendly = _value(data, 'calendlyUrl');

      if (name.isNotEmpty) _nameCtrl.text = name;
      if (phone.isNotEmpty) _phoneCtrl.text = phone;
      if (agency.isNotEmpty) _agencyNameCtrl.text = agency;
      if (address.isNotEmpty) _agencyAddressCtrl.text = address;
      if (city.isNotEmpty) _agencyCityCtrl.text = city;
      if (state.isNotEmpty) _agencyStateCtrl.text = state;
      if (zip.isNotEmpty) _agencyZipCtrl.text = zip;
      if (calendly.isNotEmpty) _calendlyUrlCtrl.text = calendly;
    });
  }

  Widget _previewLine(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          children: [
            TextSpan(
              text: "$label: ",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String? _validatePassword(String? pw) {
    if (pw == null || pw.isEmpty) return null;
    if (pw.length < 10) return AppStrings.of(context).tenCharsMin;
    if (!RegExp(r'[A-Z]').hasMatch(pw)) {
      return AppStrings.of(context).oneUppercaseRequired;
    }
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(pw)) {
      return AppStrings.of(context).oneSpecialRequired;
    }
    return null;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final store = SecureStore();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final res = await ApiService.updateAgentProfile(
        email: _emailCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        agencyName: _agencyNameCtrl.text.trim().isNotEmpty
            ? _agencyNameCtrl.text.trim()
            : null,
        agencyAddress: _agencyAddressCtrl.text.trim().isNotEmpty
            ? _agencyAddressCtrl.text.trim()
            : null,
        agencyStreet: _agencyAddressCtrl.text.trim().isNotEmpty
            ? _agencyAddressCtrl.text.trim()
            : null,
        agencyCity: _agencyCityCtrl.text.trim().isNotEmpty
            ? _agencyCityCtrl.text.trim()
            : null,
        agencyState: _agencyStateCtrl.text.trim().isNotEmpty
            ? _agencyStateCtrl.text.trim()
            : null,
        agencyZip: _agencyZipCtrl.text.trim().isNotEmpty
            ? _agencyZipCtrl.text.trim()
            : null,
        agencyPhone: _agencyPhoneCtrl.text.trim().isNotEmpty
            ? _agencyPhoneCtrl.text.trim()
            : null,
        calendlyUrl: _calendlyUrlCtrl.text.trim().isNotEmpty
            ? _calendlyUrlCtrl.text.trim()
            : null,
        password:
            _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text.trim() : null,
      );

      if (res['success'] != true) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
              content:
                  Text(res['error'] ?? AppStrings.of(context).updateFailed)),
        );
        return;
      }

      await store.setString('agentName', _nameCtrl.text.trim());
      await store.setString('agentPhone', _phoneCtrl.text.trim());
      await store.setString('agentEmail', _emailCtrl.text.trim());
      await store.setString('agencyName', _agencyNameCtrl.text.trim());
      await store.setString('agencyAddress', _agencyAddressCtrl.text.trim());
      await store.setString('agencyPhone', _agencyPhoneCtrl.text.trim());
      await store.setString('agentCalendlyUrl', _calendlyUrlCtrl.text.trim());

      // 🔥 SAVE NEW ADDRESS FIELDS
      await store.setString('agencyCity', _agencyCityCtrl.text.trim());
      await store.setString('agencyState', _agencyStateCtrl.text.trim());
      await store.setString('agencyZip', _agencyZipCtrl.text.trim());

      if (_passwordCtrl.text.isNotEmpty) {
        await store.setString('agentPassword', _passwordCtrl.text.trim());
      }

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).agentProfileUpdated)),
      );
      navigator.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).myAgentProfile)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).fullName),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).requiredField
                    : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _emailCtrl,
                enabled: false,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).emailCannotChange,
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scanningCard ? null : _scanBusinessCard,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.lightBlueAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _scanningCard
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.badge),
                  label: Text(
                    _scanningCard
                        ? AppStrings.of(context).scanningBusinessCard
                        : AppStrings.of(context).scanBusinessCard,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).phone),
                validator: (v) => v == null || v.isEmpty
                    ? AppStrings.of(context).requiredField
                    : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyNameCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agencyName),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyAddressCtrl,
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agencyAddress),
                maxLines: 2,
              ),

              const SizedBox(height: 12),

              // 🔥 NEW CITY / STATE / ZIP
              TextFormField(
                controller: _agencyCityCtrl,
                decoration:
                    InputDecoration(labelText: AppStrings.of(context).city),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _agencyStateCtrl,
                      decoration: InputDecoration(
                          labelText: AppStrings.of(context).state),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _agencyZipCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "ZIP"),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _agencyPhoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
                decoration: InputDecoration(
                    labelText: AppStrings.of(context).agencyPhoneNumber),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _calendlyUrlCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).calendlyLink,
                  hintText: "https://calendly.com/your-link",
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return null;
                  final uri = Uri.tryParse(value);
                  if (uri == null ||
                      !uri.hasScheme ||
                      !['http', 'https'].contains(uri.scheme.toLowerCase())) {
                    return AppStrings.of(context).enterValidLink;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),

              Text(
                AppStrings.of(context).changePasswordOptional,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).newPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: _validatePassword,
              ),
              const SizedBox(height: 8),
              PasswordRules(controller: _passwordCtrl),

              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).confirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirm ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                ),
                validator: (v) =>
                    _passwordCtrl.text.isNotEmpty && v != _passwordCtrl.text
                        ? AppStrings.of(context).passwordsDontMatchCurly
                        : null,
              ),

              const SizedBox(height: 24),

              _loading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saveProfile,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.save),
                        label: Text(
                          AppStrings.of(context).saveChanges,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
