import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/services/profile_share_crypto_service.dart';
import 'package:vitalink/services/profile_update_sync_service.dart';

void main() {
  test('Medication RxNorm fields survive JSON and old medication JSON loads', () {
    final medication = Medication(
      name: 'Eliquis',
      dose: '5 mg',
      rxcui: '1364447',
      ndc: '00003-0894-21',
      ndcSource: 'label',
      drugForm: 'Oral Tablet',
      drugType: 'brand',
      daysSupply: 30,
      refills: '2',
      matchStatus: 'confirmed',
    );
    final restored = Medication.fromJson(
      jsonDecode(jsonEncode(medication.toJson())) as Map<String, dynamic>,
    );

    expect(restored.rxcui, medication.rxcui);
    expect(restored.ndc, medication.ndc);
    expect(restored.ndcSource, 'label');
    expect(restored.drugForm, 'Oral Tablet');
    expect(restored.drugType, 'brand');
    expect(restored.daysSupply, 30);
    expect(restored.refills, '2');
    expect(restored.matchStatus, 'confirmed');

    final legacy = Medication.fromJson({'name': 'Lisinopril', 'dose': '10 mg'});
    expect(legacy.name, 'Lisinopril');
    expect(legacy.rxcui, isEmpty);
    expect(legacy.daysSupply, isNull);
    expect(legacy.matchStatus, isEmpty);
  });

  test('RxNorm fields survive server and encrypted profile sharing round trips',
      () async {
    final profile = Profile(
      fullName: 'Test Client',
      meds: [
        Medication(
          name: 'Metoprolol succinate ER',
          dose: '25 mg',
          rxcui: '866427',
          ndc: '00078-0520-05',
          ndcSource: 'representative',
          drugForm: 'Extended Release Oral Tablet',
          drugType: 'generic',
          daysSupply: 90,
          refills: '3',
          matchStatus: 'confirmed',
        ),
      ],
    );

    final serverRoundTrip = Profile.fromJson(
      jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>,
    );
    expect(serverRoundTrip.meds.single.rxcui, '866427');
    expect(serverRoundTrip.meds.single.daysSupply, 90);
    final syncPayload = ProfileUpdateSyncService().buildPayload(profile);
    final syncedMedication = (syncPayload['meds'] as List).single as Map;
    expect(syncedMedication['rxcui'], '866427');
    expect(syncedMedication['ndcSource'], 'representative');
    expect(syncedMedication['daysSupply'], 90);

    final crypto = ProfileShareCryptoService();
    final key = crypto.generateKey();
    final encrypted = await crypto.encryptJson(profile.toJson(), key);
    final decrypted = await crypto.decryptJson(encrypted, key);
    final sharedRoundTrip = Profile.fromJson(decrypted);
    expect(sharedRoundTrip.meds.single.ndcSource, 'representative');
    expect(sharedRoundTrip.meds.single.matchStatus, 'confirmed');
  });
}
