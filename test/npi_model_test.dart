import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/widgets/npi_verification_widgets.dart';

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
    expect(doctor.isPrimaryCareProvider, isFalse);
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
      isPrimaryCareProvider: true,
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
      pharmacyVerifiedBy: '7',
    );

    final restoredDoctor = Doctor.fromJson(doctor.toJson());
    final restoredMedication = Medication.fromJson(medication.toJson());

    expect(restoredDoctor.npi, '1234567890');
    expect(restoredDoctor.verificationStatus, 'verified');
    expect(restoredDoctor.verifiedAt, verifiedAt);
    expect(restoredDoctor.isPrimaryCareProvider, isTrue);
    expect(restoredMedication.pharmacyNpi, '0987654321');
    expect(restoredMedication.pharmacyVerificationStatus, 'verified');
    expect(restoredMedication.pharmacyVerifiedBy, '7');
  });

  test('provider specialty and primary-care role remain independent', () {
    final doctor = Doctor(
      name: 'Jane Smith',
      specialty: 'Internal Medicine',
      isPrimaryCareProvider: true,
    );

    final restored = Doctor.fromJson(doctor.toJson());

    expect(restored.specialty, 'Internal Medicine');
    expect(restored.isPrimaryCareProvider, isTrue);
  });

  test('every existing doctor type remains available for NPI narrowing', () {
    expect(npiDoctorSpecialtyOptions, contains('Primary'));
    expect(npiDoctorSpecialtyOptions, contains('Cardiologist'));
    expect(npiDoctorSpecialtyOptions, contains('Pain Management'));
    expect(npiDoctorSpecialtyOptions.last, 'Other');
  });
}
