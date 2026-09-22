import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/models.dart';

void main() {
  test('legacy doctor and medication JSON remain backward compatible', () {
    final doctor = Doctor.fromJson({
      'name': 'Jane Smith',
      'specialty': 'Primary',
      'clinic': 'Main Clinic',
      'phone': '402-555-1212',
    });
    final medication = Medication.fromJson({
      'name': 'Example',
      'prescriber': 'Example Pharmacy',
    });

    expect(doctor.verificationStatus, 'unverified');
    expect(doctor.npi, isNull);
    expect(doctor.npiCandidates, isEmpty);
    expect(medication.pharmacyVerificationStatus, 'unverified');
    expect(medication.pharmacyNpi, isNull);
    expect(medication.pharmacyNpiCandidates, isEmpty);
  });

  test('verified NPI metadata survives a JSON round trip', () {
    final verifiedAt = DateTime.utc(2026, 9, 21, 12);
    final doctor = Doctor(
      name: 'Jane Smith',
      npi: '1234567890',
      verificationStatus: 'verified',
      npiCandidates: [
        {'npi': '1234567890', 'displayName': 'JANE SMITH'},
      ],
      verifiedAt: verifiedAt,
      verifiedBy: 'auto',
    );
    final medication = Medication(
      name: 'Example',
      prescriber: 'Example Pharmacy',
      pharmacyNpi: '0987654321',
      pharmacyVerificationStatus: 'verified',
      pharmacyNpiCandidates: [
        {'npi': '0987654321', 'displayName': 'EXAMPLE PHARMACY'},
      ],
      pharmacyVerifiedAt: verifiedAt,
      pharmacyVerifiedBy: 'agent:7',
    );

    final restoredDoctor = Doctor.fromJson(doctor.toJson());
    final restoredMedication = Medication.fromJson(medication.toJson());

    expect(restoredDoctor.npi, '1234567890');
    expect(restoredDoctor.verificationStatus, 'verified');
    expect(restoredDoctor.verifiedAt, verifiedAt);
    expect(restoredMedication.pharmacyNpi, '0987654321');
    expect(restoredMedication.pharmacyVerificationStatus, 'verified');
    expect(restoredMedication.pharmacyVerifiedBy, 'agent:7');
  });
}
