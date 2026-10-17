import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/screen_strings.dart';
import '../services/api_service.dart';
import '../services/device_id.dart';
import '../services/secure_store.dart';

typedef AgentAccessLoader = Future<Map<String, dynamic>> Function(
    String userId);
typedef AgentAccessUpdater = Future<Map<String, dynamic>> Function({
  required String userId,
  required String action,
  Map<String, dynamic> values,
});

/// Account-holder agent preferences, shown only on Settings.
class AgentPreferences extends StatefulWidget {
  const AgentPreferences({
    super.key,
    this.loadAccess = ApiService.getAccountAccess,
    this.updateAccess = ApiService.updateAccountAccess,
  });

  final AgentAccessLoader loadAccess;
  final AgentAccessUpdater updateAccess;

  @override
  State<AgentPreferences> createState() => _AgentPreferencesState();
}

class _AgentPreferencesState extends State<AgentPreferences> {
  bool _loading = true;
  bool _hasUser = false;
  bool _hasAgent = false;
  bool? _agentMessagesEnabled;
  String? _relationshipStatus;
  String? _error;
  final Map<String, bool> _prospectMessages = {
    'medicare': false,
    'life': false
  };
  final Map<String, String> _prospectConsentText = {};
  bool _updatingMessages = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final userId = await SecureStore().getString('userId');
      if (!mounted) return;
      if (userId == null || userId.isEmpty) {
        setState(() {
          _hasUser = false;
          _loading = false;
        });
        return;
      }
      setState(() => _hasUser = true);
      final result = await widget.loadAccess(userId);
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() {
          _loading = false;
          _error = result['error']?.toString() ??
              AppStrings.of(context).unableToCheckAccess;
        });
        return;
      }
      final details = Map<String, dynamic>.from(result['access'] as Map? ?? {});
      final consents =
          Map<String, dynamic>.from(details['prospectConsents'] as Map? ?? {});
      final options =
          Map<String, dynamic>.from(details['prospectOptions'] as Map? ?? {});
      setState(() {
        _hasAgent = details['agentId'] != null;
        _relationshipStatus = details['relationshipStatus']?.toString();
        _agentMessagesEnabled = _relationshipStatus == 'confirmed_client'
            ? details['canMessage'] == true
            : null;
        for (final category in _prospectMessages.keys) {
          _prospectMessages[category] =
              (consents[category] as Map?)?['status'] == 'granted';
          final option = options[category];
          if (option is Map && option['text'] != null) {
            _prospectConsentText[category] = option['text'].toString();
          }
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppStrings.of(context).unableToCheckAccess;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _submitAccess({
    required String userId,
    required String action,
    Map<String, dynamic> values = const {},
  }) async {
    try {
      return await widget.updateAccess(
          userId: userId, action: action, values: values);
    } catch (_) {
      return {'success': false};
    }
  }

  void _showActionError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    if (confirmed != true || !mounted) return;
    setState(() => _updatingMessages = true);
    final store = SecureStore();
    final userId = await store.getString('userId');
    if (userId == null) {
      if (mounted) setState(() => _updatingMessages = false);
      return;
    }
    final result = await _submitAccess(
      userId: userId,
      action: 'disconnect',
      values: {
        'deviceId': await DeviceId.getOrCreate(),
        'platform': Platform.isIOS ? 'ios' : 'android',
      },
    );
    if (!mounted) return;
    setState(() => _updatingMessages = false);
    if (result['success'] == true) {
      Navigator.pushNamedAndRemoveUntil(
          context, '/account_access', (_) => false);
    } else {
      _showActionError(result['error']?.toString() ??
          AppStrings.of(context).unableToDisconnectAgent);
    }
  }

  Future<void> _setAgentMessages(bool enabled) async {
    if (_updatingMessages) return;
    setState(() => _updatingMessages = true);
    if (!enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final strings = AppStrings.of(ctx);
          return AlertDialog(
            title: Text(strings.turnOffAgentMessagesQ),
            content: Text(strings.turnOffAgentMessagesBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(strings.turnOffMessages),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(strings.keepMessagesOn),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _updatingMessages = false);
        return;
      }
    }
    final store = SecureStore();
    final userId = await store.getString('userId');
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _updatingMessages = false);
      return;
    }
    final result = await _submitAccess(
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
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _updatingMessages = false);
      return;
    }
    final result = await _submitAccess(
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

  @override
  Widget build(BuildContext context) {
    if (!_hasUser || (!_loading && _error == null && !_hasAgent)) {
      return const SizedBox.shrink();
    }
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.myAgent,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!),
            TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(strings.reloadInfo)),
          ] else ...[
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
                          : (value) => _setProspectMessages('medicare', value),
                      secondary: const Icon(Icons.health_and_safety_outlined),
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
                      title: Text(AppStrings.of(context).lifeInsuranceMessages),
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
              onPressed: _updatingMessages ? null : _disconnectAgent,
              icon: const Icon(Icons.link_off),
              label: Text(AppStrings.of(context).changeOrDisconnectAgent),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
