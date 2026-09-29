import 'api_service.dart';
import 'secure_store.dart';
import '../models.dart';

Map<String, dynamic> selectNpiIdentity({
  String? agentId,
  String? agentToken,
  String? userId,
  String? userToken,
}) {
  if (userId != null &&
      userId.isNotEmpty &&
      userToken != null &&
      userToken.isNotEmpty) {
    return {'userId': userId};
  }
  if (agentId != null &&
      agentId.isNotEmpty &&
      agentToken != null &&
      agentToken.isNotEmpty) {
    return {'agentId': int.tryParse(agentId)};
  }
  return {'userId': userId};
}

class NpiLookupResult {
  final String status;
  final String? npi;
  final List<Map<String, dynamic>> candidates;
  final String? verifiedBy;
  final String? error;

  const NpiLookupResult({
    required this.status,
    this.npi,
    this.candidates = const [],
    this.verifiedBy,
    this.error,
  });

  bool get isVerified => status == 'verified' && npi != null;
  bool get hasError => status == 'error';

  factory NpiLookupResult.fromJson(Map<String, dynamic> json) {
    return NpiLookupResult(
      status: (json['verificationStatus'] ?? 'unverified').toString(),
      npi: json['npi']?.toString(),
      candidates: (json['candidates'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      verifiedBy: json['verifiedBy']?.toString(),
      error: json['error']?.toString(),
    );
  }
}

Map<String, dynamic>? verifiedProviderCandidate(Doctor doctor) {
  if (doctor.verificationStatus != 'verified' || doctor.npi == null) {
    return null;
  }
  for (final candidate in doctor.npiCandidates) {
    if (candidate['npi']?.toString() == doctor.npi) return candidate;
  }
  return null;
}

String formatRegistryPostalCode(Object? value) {
  final raw = value?.toString().trim() ?? '';
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 9) {
    return '${digits.substring(0, 5)}-${digits.substring(5)}';
  }
  return raw;
}

void applyProviderLookupResult(Doctor doctor, NpiLookupResult result) {
  doctor.npi = result.npi;
  doctor.verificationStatus = result.status;
  doctor.npiCandidates = result.candidates;
  doctor.verifiedAt = result.isVerified ? DateTime.now() : null;
  doctor.verifiedBy = result.isVerified ? result.verifiedBy ?? 'auto' : null;
  doctor.isVaProvider = false;
  doctor.vaFacility = null;
  doctor.vaServiceLine = null;
  doctor.vaVerifiedAt = null;
  if (result.isVerified && doctor.specialty.trim().isEmpty) {
    doctor.specialty =
        verifiedProviderCandidate(doctor)?['taxonomy']?.toString().trim() ?? '';
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
    final userToken = await _store.getString('userSessionToken');

    // Doctors and medications belong to the user profile. Agents may also
    // have a user account on the same device, so prefer that active session.
    return selectNpiIdentity(
      agentId: agentId,
      agentToken: agentToken,
      userId: userId,
      userToken: userToken,
    );
  }

  Future<NpiLookupResult> lookup({
    required String entityType,
    required String name,
    String? city,
    String? state,
    String? postalCode,
    String? specialty,
    String? phone,
    bool? mailOrder,
    bool includeVa = false,
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
      phone: phone,
      mailOrder: mailOrder,
      includeVa: includeVa,
    );

    if (response['success'] != true) {
      return NpiLookupResult(
        status: 'error',
        error: response['error']?.toString() ?? 'Provider lookup failed',
      );
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
