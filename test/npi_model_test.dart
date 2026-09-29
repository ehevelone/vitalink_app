import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/services/npi_verification_service.dart';
import 'package:vitalink/widgets/npi_verification_widgets.dart';

void main() {
  test(
    'NPI lookup prefers the active user session on a dual-account device',
    () {
      final identity = selectNpiIdentity(
        agentId: '42',
        agentToken: 'saved-agent-token',
        userId: '84',
        userToken: 'active-user-token',
      );

      expect(identity, {'userId': '84'});
    },
  );

  test('NPI lookup still supports an agent-only session', () {
    final identity = selectNpiIdentity(
      agentId: '42',
      agentToken: 'active-agent-token',
    );

    expect(identity, {'agentId': 42});
  });

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
    expect(doctor.isVaProvider, isFalse);
    expect(medication.pharmacyVerificationStatus, 'unverified');
    expect(medication.pharmacyNpi, isNull);
    expect(medication.pharmacyNpiCandidates, isEmpty);
    expect(medication.pharmacyFulfillmentType, isNull);
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
      pharmacyFulfillmentType: 'mail_order',
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
    expect(restoredMedication.pharmacyFulfillmentType, 'mail_order');
  });

  test('Veteran and VA provider details survive JSON round trips', () {
    final verifiedAt = DateTime.utc(2026, 9, 27, 12);
    final profile = Profile(
      fullName: 'Test Veteran',
      isVeteran: true,
      usesVaHealthcare: true,
    );
    final doctor = Doctor(
      name: 'Hoa Nguyen',
      verificationStatus: 'va_verified',
      isVaProvider: true,
      vaFacility: 'Nebraska/Western Iowa HCS (636)',
      vaServiceLine: 'Primary Care',
      vaVerifiedAt: verifiedAt,
    );

    final restoredProfile = Profile.fromJson(profile.toJson());
    final restoredDoctor = Doctor.fromJson(doctor.toJson());

    expect(restoredProfile.isVeteran, isTrue);
    expect(restoredProfile.usesVaHealthcare, isTrue);
    expect(restoredDoctor.isVaProvider, isTrue);
    expect(restoredDoctor.vaFacility, 'Nebraska/Western Iowa HCS (636)');
    expect(restoredDoctor.vaVerifiedAt, verifiedAt);
  });

  test('legacy Veteran profile keys remain compatible', () {
    expect(Profile.fromJson({'id': '1', 'is_veteran': true}).isVeteran, isTrue);
    expect(Profile.fromJson({'id': '2', 'veteran': true}).isVeteran, isTrue);
    expect(
      Profile.fromJson({
        'id': '3',
        'is_veteran': true,
        'uses_va_healthcare': true,
      }).usesVaHealthcare,
      isTrue,
    );
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

  test(
    'single verified NPI fills a blank specialty and retains registry details',
    () {
      final doctor = Doctor(name: 'Doty, Brandon');
      applyProviderLookupResult(
        doctor,
        const NpiLookupResult(
          status: 'verified',
          npi: '1265221683',
          verifiedBy: 'auto',
          candidates: [
            {
              'npi': '1265221683',
              'displayName': 'BRANDON DOTY',
              'taxonomy': 'Internal Medicine',
              'city': 'OMAHA',
              'state': 'NE',
            },
          ],
        ),
      );

      final restored = Doctor.fromJson(doctor.toJson());
      expect(restored.specialty, 'Internal Medicine');
      expect(restored.isPrimaryCareProvider, isFalse);
      expect(restored.npi, '1265221683');
      expect(verifiedProviderCandidate(restored)?['city'], 'OMAHA');
    },
  );

  test(
    'verified registry taxonomy does not overwrite a user-entered specialty',
    () {
      final doctor = Doctor(name: 'Jane Smith', specialty: 'My specialist');
      applyProviderLookupResult(
        doctor,
        const NpiLookupResult(
          status: 'verified',
          npi: '1234567890',
          candidates: [
            {'npi': '1234567890', 'taxonomy': 'Internal Medicine'},
          ],
        ),
      );
      expect(doctor.specialty, 'My specialist');
    },
  );

  test('registry ZIP+4 is formatted for provider display', () {
    expect(formatRegistryPostalCode('681051850'), '68105-1850');
    expect(formatRegistryPostalCode('68105'), '68105');
  });

  test('every existing doctor type remains available for NPI narrowing', () {
    expect(npiDoctorSpecialtyOptions, contains('Primary'));
    expect(npiDoctorSpecialtyOptions, contains('Cardiologist'));
    expect(
      npiDoctorSpecialtyOptions,
      contains('Psychologist / Clinical Psychologist'),
    );
    expect(npiDoctorSpecialtyOptions, contains('Clinical Social Worker'));
    expect(npiDoctorSpecialtyOptions, contains('Professional Counselor'));
    expect(npiDoctorSpecialtyOptions, contains('Mental Health Counselor'));
    expect(npiDoctorSpecialtyOptions, contains('Marriage & Family Therapist'));
    expect(
      npiDoctorSpecialtyOptions,
      contains('Psychiatric Nurse Practitioner'),
    );
    expect(npiDoctorSpecialtyOptions, contains('Addiction Counselor'));
    expect(npiDoctorSpecialtyOptions, contains('Pain Management'));
    expect(npiDoctorSpecialtyOptions.last, 'Other');
  });
}
