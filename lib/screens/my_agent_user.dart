import 'dart:convert';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/secure_store.dart';
import '../services/device_id.dart';

class MyAgentUser extends StatefulWidget {
  const MyAgentUser({super.key});

  @override
  State<MyAgentUser> createState() => _MyAgentUserState();
}

class _MyAgentUserState extends State<MyAgentUser> {
  String? _agentName;
  String? _agentPhone;
  String? _agentEmail;
  String? _agencyName;
  String? _agencyAddress;
  String? _agencyStreet;
  String? _agencyCity;
  String? _agencyState;
  String? _agencyZip;
  String? _agencyPhone;
  String? _calendlyUrl;
  String? _businessCardImageBase64;
  bool? _agentMessagesEnabled;
  String? _relationshipStatus;
  final Map<String, bool> _prospectMessages = {
    'medicare': false,
    'life': false,
  };
  final Map<String, String> _prospectConsentText = {};
  bool _updatingMessages = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  Future<void> _loadAgent() async {
    try {
      final userEmail = await AppState.getEmail();
      if (userEmail == null || userEmail.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final res = await ApiService.getUserAgent(userEmail);

      if (res["success"] == true && res["agent"] != null) {
        final agent = res["agent"];

        _agentName = agent["name"];
        _agentPhone = agent["phone"];
        _agentEmail = agent["email"];
        _agencyName = agent["agency_name"];
        _agencyAddress = agent["agency_address"];
        _agencyStreet = agent["agency_street"];
        _agencyCity = agent["agency_city"];
        _agencyState = agent["agency_state"];
        _agencyZip = agent["agency_zip"];
        _agencyPhone = agent["agency_phone"];
        _calendlyUrl = agent["calendly_url"];
        _businessCardImageBase64 = agent["business_card_image_base64"];
      }

      final userId = await SecureStore().getString('userId');
      if (userId != null && userId.isNotEmpty) {
        final access = await ApiService.getAccountAccess(userId);
        final details = Map<String, dynamic>.from(
          access['access'] as Map? ?? {},
        );
        _relationshipStatus = details['relationshipStatus']?.toString();
        if (details['relationshipStatus'] == 'confirmed_client') {
          _agentMessagesEnabled = details['canMessage'] == true;
        } else if (details['relationshipStatus'] == 'confirmed_prospect') {
          final consents = Map<String, dynamic>.from(
            details['prospectConsents'] as Map? ?? {},
          );
          for (final category in _prospectMessages.keys) {
            _prospectMessages[category] =
                (consents[category] as Map?)?['status'] == 'granted';
          }
          final options = Map<String, dynamic>.from(
            details['prospectOptions'] as Map? ?? {},
          );
          for (final category in _prospectMessages.keys) {
            final option = options[category];
            if (option is Map && option['text'] != null) {
              _prospectConsentText[category] = option['text'].toString();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Agent load error: $e");
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _call() async {
    final phone = _contactPhone;
    if (phone.isEmpty) return;

    final uri = Uri(scheme: "tel", path: phone);
    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      _showActionError(AppStrings.of(context).unableToOpenPhone);
    }
  }

  Future<void> _email() async {
    if (_agentEmail == null || _agentEmail!.isEmpty) return;
    final uri = Uri(
      scheme: "mailto",
      path: _agentEmail,
      queryParameters: {
        "subject": AppStrings.of(context).clientInquirySubject,
      },
    );
    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      _showActionError(AppStrings.of(context).unableToOpenEmail);
    }
  }

  Future<void> _openDirections() async {
    final address = _formattedAddress.replaceAll("\n", ", ").trim();
    if (address.isEmpty) return;

    final uri = Uri.https(
      "www.google.com",
      "/maps/dir/",
      {
        "api": "1",
        "destination": address,
      },
    );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      _showActionError(AppStrings.of(context).unableToOpenDirections);
    }
  }

  Future<void> _sendToAgent() async {
    Navigator.pushNamed(context, '/authorization_form');
  }

  Future<void> _schedule() async {
    final url = _calendlyUrl?.trim();
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _disconnectAgent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.of(context).disconnectFromAgentQ),
        content: Text(
          AppStrings.of(context).disconnectAgentBody(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.of(context).keepMyCurrentAgent)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppStrings.of(context).disconnectAndLock)),
        ],
      ),
    );
    if (confirmed != true) return;
    final store = SecureStore();
    final userId = await store.getString('userId');
    if (userId == null) {
      if (mounted) setState(() => _updatingMessages = false);
      return;
    }
    final result = await ApiService.updateAccountAccess(
      userId: userId,
      action: 'disconnect',
      values: {
        'deviceId': await DeviceId.getOrCreate(),
        'platform': Platform.isIOS ? 'ios' : 'android',
      },
    );
    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.pushNamedAndRemoveUntil(
          context, '/account_access', (_) => false);
    } else {
      _showActionError(result['error']?.toString() ??
          AppStrings.of(context).unableToDisconnectAgent);
    }
  }

  Future<void> _setAgentMessages(bool enabled) async {
    setState(() => _updatingMessages = true);
    final store = SecureStore();
    final userId = await store.getString('userId');
    if (userId == null) return;
    final result = await ApiService.updateAccountAccess(
      userId: userId,
      action: 'messaging_consent',
      values: {
        'messagingConsent': enabled,
        'userAttestation': true,
        'deviceId': await DeviceId.getOrCreate(),
        'platform': Platform.isIOS ? 'ios' : 'android',
      },
    );
    if (!mounted) return;
    setState(() {
      _updatingMessages = false;
      if (result['success'] == true) _agentMessagesEnabled = enabled;
    });
    if (result['success'] != true) {
      _showActionError(
        result['error']?.toString() ??
            AppStrings.of(context).unableToUpdateConsent,
      );
    }
  }

  Future<void> _setProspectMessages(String category, bool enabled) async {
    if (enabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(category == 'medicare'
              ? AppStrings.of(context).medicareMessages
              : AppStrings.of(context).lifeInsuranceMessages),
          content: Text(
            _prospectConsentText[category] ??
                AppStrings.of(context).agreeMarketingFromConnected,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.of(context).cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppStrings.of(context).iAgree),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() => _updatingMessages = true);
    final userId = await SecureStore().getString('userId');
    if (userId == null) return;
    final result = await ApiService.updateAccountAccess(
      userId: userId,
      action: 'prospect_marketing_consent',
      values: {
        'category': category,
        'granted': enabled,
        'userAttestation': true,
        'deviceId': await DeviceId.getOrCreate(),
        'platform': Platform.isIOS ? 'ios' : 'android',
      },
    );
    if (!mounted) return;
    setState(() {
      _updatingMessages = false;
      if (result['success'] == true) _prospectMessages[category] = enabled;
    });
    if (result['success'] != true) {
      _showActionError(
        result['error']?.toString() ??
            AppStrings.of(context).unableToUpdateConsent,
      );
    }
  }

  Widget _agentCardDisplay() {
    final image = _businessCardImageBase64?.trim();
    if (image != null && image.isNotEmpty) {
      final bytes = base64Decode(image);
      return Column(
        children: [
          GestureDetector(
            onTap: () => _openBusinessCard(bytes),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                cacheWidth: 1400,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _agentTextDisplay(),
        ],
      );
    }

    return _agentTextDisplay();
  }

  void _openBusinessCard(List<int> bytes) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agentTextDisplay() {
    final address = _formattedAddress;

    return Column(
      children: [
        Text(
          _agentName ?? AppStrings.of(context).noAgentAssigned,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (_agencyName?.isNotEmpty == true)
          Text(
            _agencyName!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (address.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              address,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        if (_contactPhone.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _contactPhone,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        if (_agentEmail?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _agentEmail!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        if (_contactPhone.isNotEmpty || _agentEmail?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              if (_contactPhone.isNotEmpty)
                Expanded(
                  child: _contactButton(
                    icon: Icons.phone,
                    label: AppStrings.of(context).call,
                    onPressed: _call,
                  ),
                ),
              if (_contactPhone.isNotEmpty && _agentEmail?.isNotEmpty == true)
                const SizedBox(width: 12),
              if (_agentEmail?.isNotEmpty == true)
                Expanded(
                  child: _contactButton(
                    icon: Icons.email,
                    label: AppStrings.of(context).email,
                    onPressed: _email,
                  ),
                ),
            ],
          ),
        ],
        if (address.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _contactButton(
              icon: Icons.directions,
              label: AppStrings.of(context).directions,
              onPressed: _openDirections,
            ),
          ),
        ],
      ],
    );
  }

  String get _contactPhone {
    final direct = _agentPhone?.trim() ?? "";
    if (direct.isNotEmpty) return direct;
    return _agencyPhone?.trim() ?? "";
  }

  String get _formattedAddress {
    final legacy = _agencyAddress?.trim() ?? "";
    final street = _agencyStreet?.trim() ?? "";
    final city = _agencyCity?.trim() ?? "";
    final state = _agencyState?.trim() ?? "";
    final zip = _agencyZip?.trim() ?? "";

    final cityStateZip = [
      city,
      [state, zip].where((part) => part.isNotEmpty).join(" "),
    ].where((part) => part.isNotEmpty).join(", ");

    final structured = [
      street,
      cityStateZip,
    ].where((part) => part.isNotEmpty).join("\n");

    return structured.isNotEmpty ? structured : legacy;
  }

  void _showActionError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _contactButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.lightBlueAccent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          AppStrings.of(context).myAgent,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _agentCardDisplay(),
                  ),
                ),
                if (_calendlyUrl?.isNotEmpty == true) ...[
                  _actionButton(
                    icon: Icons.calendar_month,
                    label: AppStrings.of(context).scheduleWithMyAgent,
                    light: true,
                    onPressed: _schedule,
                  ),
                  const SizedBox(height: 14),
                ],
                _actionButton(
                  icon: Icons.refresh,
                  label: AppStrings.of(context).reloadInfo,
                  onPressed: _loadAgent,
                ),
                if (_agentMessagesEnabled != null) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: SwitchListTile(
                      value: _agentMessagesEnabled!,
                      onChanged: _updatingMessages ? null : _setAgentMessages,
                      secondary: const Icon(Icons.notifications_outlined),
                      title: Text(AppStrings.of(context).messagesFromMyAgent),
                      subtitle: Text(
                        AppStrings.of(context).coverageRemindersBody,
                      ),
                    ),
                  ),
                ],
                if (_relationshipStatus == 'confirmed_prospect') ...[
                  const SizedBox(height: 14),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _prospectMessages['medicare']!,
                          onChanged: _updatingMessages
                              ? null
                              : (value) =>
                                  _setProspectMessages('medicare', value),
                          secondary:
                              const Icon(Icons.health_and_safety_outlined),
                          title: Text(AppStrings.of(context).medicareMessages),
                          subtitle: Text(
                            AppStrings.of(context).optionalMarketingFromAgent,
                          ),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          value: _prospectMessages['life']!,
                          onChanged: _updatingMessages
                              ? null
                              : (value) => _setProspectMessages('life', value),
                          secondary: const Icon(Icons.favorite_outline),
                          title: Text(
                              AppStrings.of(context).lifeInsuranceMessages),
                          subtitle: Text(
                            AppStrings.of(context).optionalMarketingFromAgent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _disconnectAgent,
                  icon: const Icon(Icons.link_off),
                  label: Text(AppStrings.of(context).changeOrDisconnectAgent),
                ),
                const SizedBox(height: 20),
                _actionButton(
                  icon: Icons.send,
                  label: AppStrings.of(context).sendMyInfoToAgent,
                  onPressed: _sendToAgent,
                ),
                const SizedBox(height: 14),
                _actionButton(
                  icon: Icons.favorite,
                  label: AppStrings.of(context).referralCenter,
                  light: true,
                  onPressed: () => Navigator.pushNamed(
                    context,
                    '/referral_center',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool light = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor:
              light ? Colors.lightBlueAccent : Colors.blue.shade700,
          foregroundColor: light ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
