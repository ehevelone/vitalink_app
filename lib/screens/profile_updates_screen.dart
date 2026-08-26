import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class ProfileUpdatesScreen extends StatefulWidget {
  const ProfileUpdatesScreen({super.key});

  @override
  State<ProfileUpdatesScreen> createState() => _ProfileUpdatesScreenState();
}

class _ProfileUpdatesScreenState extends State<ProfileUpdatesScreen> {
  final SecureStore _store = SecureStore();
  final DataRepository _repo = DataRepository();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _packages = [];

  @override
  void initState() {
    super.initState();
    _loadUpdates();
  }

  Future<void> _loadUpdates() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final userId = await _store.getString('userId');

    if (userId == null || userId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Please log in again to check profile updates.';
      });
      return;
    }

    final res = await ApiService.getProfileUpdatePackages(userId: userId);

    if (!mounted) return;

    if (res['success'] == true && res['packages'] is List) {
      setState(() {
        _packages = (res['packages'] as List)
            .whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = false;
      _error = (res['error'] ?? 'Unable to load profile updates.').toString();
    });
  }

  Future<void> _applyUpdate(Map<String, dynamic> item) async {
    final packageId = item['packageId']?.toString() ?? '';
    final packagePayload =
        Map<String, dynamic>.from(item['payload'] as Map? ?? {});
    final updatePayload =
        Map<String, dynamic>.from(packagePayload['payload'] as Map? ?? {});

    if (packageId.isEmpty || updatePayload.isEmpty) {
      _showMessage('This update could not be applied.');
      return;
    }

    await _repo.applySharedProfileUpdate(updatePayload);

    final userId = await _store.getString('userId');

    if (userId != null && userId.isNotEmpty) {
      await ApiService.markProfileUpdateApplied(
        userId: userId,
        packageId: packageId,
      );
    }

    if (!mounted) return;

    _showMessage('Profile update applied.');
    await _loadUpdates();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _sectionsLabel(Map<String, dynamic> item) {
    final payload = Map<String, dynamic>.from(item['payload'] as Map? ?? {});
    final sections = payload['allowedSections'];

    if (sections is! List || sections.isEmpty) {
      return 'Emergency profile';
    }

    return sections
        .map((s) => s.toString().replaceAll('_', ' '))
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Updates'),
        backgroundColor: const Color(0xFF0E5A88),
      ),
      body: Container(
        color: Colors.black,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadUpdates,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Connected profile updates',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Updates are temporarily stored, encrypted, and removed after connected devices apply them.',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 18),
                    if (_error != null)
                      _InfoCard(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    else if (_packages.isEmpty)
                      const _InfoCard(
                        child: Text(
                          'No profile updates are waiting right now.',
                          style: TextStyle(color: Colors.white),
                        ),
                      )
                    else
                      ..._packages.map((item) {
                        final profileName =
                            item['profileName']?.toString().trim();

                        return _InfoCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profileName?.isNotEmpty == true
                                    ? profileName!
                                    : 'Shared Profile',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _sectionsLabel(item),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF78C7E7),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  onPressed: () => _applyUpdate(item),
                                  child: const Text(
                                    'Apply Update',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF78C7E7).withValues(alpha: .35)),
      ),
      child: child,
    );
  }
}
