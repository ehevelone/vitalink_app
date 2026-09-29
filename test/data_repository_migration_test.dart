import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/services/data_repository.dart';
import 'package:vitalink/services/secure_store.dart';

class MemorySecureStore extends SecureStore {
  final Map<String, String> values = {};

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy profile ID migration preserves all member data', () async {
    final legacy = Profile(
      id: 'legacy-profile-1',
      fullName: 'Erik Hevelone',
      dob: '01/02/1960',
      userPhone: '402-555-1212',
      address: '123 Main St',
      city: 'Omaha',
      state: 'NE',
      zip: '68114',
      isVeteran: true,
      usesVaHealthcare: true,
      meds: [Medication(name: 'Example Medication', dose: '10 mg')],
      doctors: [
        Doctor(
          name: 'HOA THUY NGUYEN',
          npi: '1275201147',
          verificationStatus: 'verified',
        ),
      ],
      emergency: EmergencyInfo(
        contact: 'Emergency Contact',
        phone: '402-555-9999',
        allergies: 'Penicillin',
      ),
    );
    SharedPreferences.setMockInitialValues({
      'profiles_json': jsonEncode([legacy.toJson()]),
      'active_profile_index': 0,
    });

    final migrated = await DataRepository(MemorySecureStore()).loadProfile();

    expect(migrated.id, isNot('legacy-profile-1'));
    expect(migrated.id.length, greaterThanOrEqualTo(30));
    expect(migrated.fullName, 'Erik Hevelone');
    expect(migrated.dob, '01/02/1960');
    expect(migrated.address, '123 Main St');
    expect(migrated.isVeteran, isTrue);
    expect(migrated.usesVaHealthcare, isTrue);
    expect(migrated.meds.single.name, 'Example Medication');
    expect(migrated.doctors.single.npi, '1275201147');
    expect(migrated.emergency.contact, 'Emergency Contact');
    expect(migrated.emergency.allergies, 'Penicillin');

    final saved = await DataRepository(MemorySecureStore()).loadProfile();
    expect(saved.id, migrated.id);
    expect(saved.meds.single.name, 'Example Medication');
    expect(saved.doctors.single.name, 'HOA THUY NGUYEN');
  });
}
