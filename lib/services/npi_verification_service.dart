import 'api_service.dart';
import 'secure_store.dart';

class NpiLookupResult {
  final String status;
  final String? npi;
  final List<Map<String, dynamic>> candidates;
  final String? verifiedBy;

  const NpiLookupResult({
    required this.status,
    this.npi,
    this.candidates = const [],
    this.verifiedBy,
  });

  bool get isVerified => status == 'verified' && npi != null;

  factory NpiLookupResult.fromJson(Map<String, dynamic> json) {
    return NpiLookupResult(
      status: (json['verificationStatus'] ?? 'unverified').toString(),
      npi: json['npi']?.toString(),
      candidates: (json['candidates'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      verifiedBy: json['verifiedBy']?.toString(),
    );
  }
}

class NpiVerificationService {
  final SecureStore _store;

  NpiVerificationService([SecureStore? store])
      : _store = store ?? SecureStore();

  Future<Map<String, dynamic>> _identity() async {
    final agentId = await _store.getString('agentId');
    final agentToken = await _store.getString('agentSessionToken');
    final userId = await _store.getString('userId');

    if (agentId != null &&
        agentId.isNotEmpty &&
        agentToken != null &&
        agentToken.isNotEmpty) {
      return {'agentId': int.tryParse(agentId)};
    }
    return {'userId': userId};
  }

  Future<NpiLookupResult> lookup({
    required String entityType,
    required String name,
    String? city,
    String? state,
    String? postalCode,
    String? specialty,
  }) async {
    if (name.trim().isEmpty) {
      return const NpiLookupResult(status: 'unverified');
    }

    final response = await ApiService.lookupNpi(
      identity: await _identity(),
      entityType: entityType,
      name: name.trim(),
      city: city,
      state: state,
      postalCode: postalCode,
      specialty: specialty,
    );

    if (response['success'] != true) {
      return const NpiLookupResult(status: 'unverified');
    }
    return NpiLookupResult.fromJson(response);
  }

  Future<Map<String, dynamic>?> confirm({
    required String entityType,
    required String searchedName,
    required Map<String, dynamic> candidate,
  }) async {
    final response = await ApiService.confirmNpi(
      identity: await _identity(),
      entityType: entityType,
      searchedName: searchedName,
      candidate: candidate,
    );
    if (response['success'] != true) return null;
    final confirmed = Map<String, dynamic>.from(
      response['candidate'] as Map? ?? candidate,
    );
    confirmed['verifiedBy'] = response['verifiedBy'];
    return confirmed;
  }
}
