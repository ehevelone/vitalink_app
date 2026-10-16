import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalink/services/drug_lookup_service.dart';
import 'package:vitalink/services/secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStore store;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = SecureStore();
    await store.setString('userId', '42');
    await store.setString('userSessionToken', 'session-token');
  });

  test('verify sends user auth and parses a sure match', () async {
    final service = DrugLookupService(
      store: store,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['userId'], '42');
        expect(body['sessionToken'], 'session-token');
        expect(body['action'], 'verify');
        return http.Response(jsonEncode({
          'success': true,
          'status': 'sure',
          'match': {
            'rxcui': '197943',
            'displayName': 'methocarbamol 500 MG Oral Tablet',
            'strength': '500 MG',
            'form': 'Oral Tablet',
            'drugType': 'generic',
            'ndc': '00000-0000-00',
            'ndcSource': 'label',
          },
        }), 200);
      }),
    );

    final result = await service.verify(name: 'methocarbamol', dose: '500 mg');
    expect(result.isSure, isTrue);
    expect(result.match!.rxcui, '197943');
    expect(result.match!.ndcSource, 'label');
  });

  test('no match is distinct from unavailable and service errors never throw',
      () async {
    final noMatch = DrugLookupService(
      store: store,
      client: MockClient((_) async =>
          http.Response('{"success":true,"status":"no_match"}', 200)),
    );
    expect(
      (await noMatch.verify(name: 'metformin ER', dose: '500 mg')).status,
      'no_match',
    );

    final unavailable = DrugLookupService(
      store: store,
      client: MockClient((_) async => http.Response('not json', 503)),
    );
    expect(
      (await unavailable.verify(name: 'metformin', dose: '500 mg'))
          .isUnavailable,
      isTrue,
    );

    final timedOut = DrugLookupService(
      store: store,
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('{"success":true,"status":"no_match"}', 200);
      }),
    );
    expect(
      (await timedOut.verify(name: 'metformin', dose: '500 mg')).isUnavailable,
      isTrue,
    );
  });

  test('search, strengths and select parse clean response models', () async {
    final service = DrugLookupService(
      store: store,
      client: MockClient((request) async {
        final action = (jsonDecode(request.body) as Map<String, dynamic>)['action'];
        if (action == 'search') {
          return http.Response(
            '{"success":true,"results":[{"name":"methocarbamol"}]}',
            200,
          );
        }
        final product = {
          'rxcui': '197943',
          'displayName': 'methocarbamol 500 MG Oral Tablet',
          'strength': '500 MG',
          'form': 'Oral Tablet',
          'drugType': 'generic',
          'ndc': '',
          'ndcSource': '',
        };
        return http.Response(
          jsonEncode({
            'success': true,
            if (action == 'select') 'result': product else 'results': [product],
          }),
          200,
        );
      }),
    );

    expect((await service.search('metho')).names, ['methocarbamol']);
    expect((await service.strengths('methocarbamol')).products.single.rxcui,
        '197943');
    expect((await service.select('197943')).match!.rxcui, '197943');
  });

  test('friendly RxNorm names cover common outpatient forms', () {
    final cases = {
      '24 HR metoprolol succinate 25 MG Extended Release Oral Capsule':
          'Metoprolol succinate ER 25 mg capsule',
      '200 ACTUAT albuterol 0.09 MG/ACTUAT Metered Dose Inhaler':
          'Albuterol 90 mcg/puff inhaler (200 puffs)',
      'apixaban 5 MG Oral Tablet [Eliquis]':
          'Eliquis (apixaban) 5 mg tablet',
      'omeprazole 40 MG Delayed Release Oral Capsule':
          'Omeprazole DR 40 mg capsule',
      'amlodipine 5 MG Oral Tablet': 'Amlodipine 5 mg tablet',
      'gabapentin 300 MG Oral Capsule': 'Gabapentin 300 mg capsule',
      'insulin glargine 100 UNT/ML Pen Injector':
          'Insulin glargine 100 units/mL pen',
      'latanoprost 0.05 MG/ML Ophthalmic Solution':
          'Latanoprost 0.05 mg/mL ophthalmic solution',
      'fluticasone propionate 0.05 MG/ACTUAT Metered Dose Nasal Spray':
          'Fluticasone propionate 50 mcg/puff metered dose nasal spray',
      'prednisone 10 MG Oral Tablet': 'Prednisone 10 mg tablet',
      'potassium chloride 10 MEQ Extended Release Oral Tablet':
          'Potassium chloride ER 10 mEq tablet',
      'ergocalciferol 1.25 MG Oral Capsule':
          'Ergocalciferol 1.25 mg capsule',
      'tiotropium 0.018 MG Inhalation Powder [Spiriva]':
          'Spiriva (tiotropium) 0.018 mg (18 mcg) inhalation powder',
      'budesonide 0.08 MG/ACTUAT / formoterol fumarate 0.0045 MG/ACTUAT Metered Dose Inhaler [Symbicort]':
          'Symbicort (budesonide / formoterol fumarate) 80 mcg/puff / 4.5 mcg/puff inhaler',
      'tiotropium 0.00125 MG/ACTUAT Inhalation Spray [Spiriva]':
          'Spiriva (tiotropium) 1.25 mcg/puff inhalation spray',
      'levothyroxine sodium 0.025 MG Oral Tablet':
          'Levothyroxine sodium 0.025 mg (25 mcg) tablet',
      'tamsulosin hydrochloride 0.4 MG Oral Capsule':
          'Tamsulosin hydrochloride 0.4 mg (400 mcg) capsule',
      'Sensor 200 ACTUAT albuterol 0.09 MG/ACTUAT Dry Powder Inhaler [ProAir]':
          'ProAir (albuterol) 90 mcg/puff dry powder inhaler (200 puffs)',
      '3 ML insulin glargine 100 UNT/ML Pen Injector [Lantus]':
          'Lantus (insulin glargine) 100 units/mL pen (3 mL)',
      '0.25 MG, 0.5 MG Dose 3 ML semaglutide 0.68 MG/ML Pen Injector [Ozempic]':
          'Ozempic (semaglutide) pen, 0.25 mg or 0.5 mg dose (3 mL)',
    };
    for (final entry in cases.entries) {
      expect(friendlyDrugName(entry.key), entry.value, reason: entry.key);
    }
  });

  test('lookalike products merge into one client choice', () {
    const first = DrugProduct(
      rxcui: '1',
      rxNormName: 'NDA021457 200 ACTUAT albuterol 0.09 MG/ACTUAT Metered Dose Inhaler',
      strength: '0.09 MG/ACTUAT',
      form: 'Metered Dose Inhaler',
      drugType: 'generic',
      ndc: '',
      ndcSource: '',
    );
    const second = DrugProduct(
      rxcui: '2',
      rxNormName: '200 ACTUAT albuterol 0.09 MG/ACTUAT Metered Dose Inhaler',
      strength: '0.09 MG/ACTUAT',
      form: 'Metered Dose Inhaler',
      drugType: 'generic',
      ndc: '',
      ndcSource: '',
    );
    expect(mergeFriendlyDrugChoices([first, second]), hasLength(1));
  });

  test('different release products remain distinct when friendly text collides', () {
    DrugProduct product(String id, String name) => DrugProduct(
          rxcui: id,
          rxNormName: name,
          strength: '500 MG',
          form: 'Extended Release Oral Tablet',
          drugType: 'generic',
          ndc: '',
          ndcSource: '',
        );

    final choices = mergeFriendlyDrugChoices([
      product('1',
          '24 HR metformin hydrochloride 500 MG Extended Release Oral Tablet'),
      product('2',
          'Osmotic 24 HR metformin hydrochloride 500 MG Extended Release Oral Tablet'),
      product('3',
          'Modified 24 HR metformin hydrochloride 500 MG Extended Release Oral Tablet'),
    ]);

    expect(choices, hasLength(3));
    expect(choices.map((item) => item.friendlyName), [
      'Metformin hydrochloride ER 500 mg tablet',
      'Metformin hydrochloride ER 500 mg tablet (osmotic)',
      'Metformin hydrochloride ER 500 mg tablet (modified-release)',
    ]);
  });

  test('unknown friendly-name collisions use option numbers, never RxCUI', () {
    DrugProduct product(String id, String name) => DrugProduct(
          rxcui: id,
          rxNormName: name,
          strength: '5 MG',
          form: 'Oral Tablet',
          drugType: 'generic',
          ndc: '',
          ndcSource: '',
        );
    final choices = mergeFriendlyDrugChoices([
      product('111', 'example drug 5 MG Oral Tablet'),
      product('222', '24 HR example drug 5 MG Oral Tablet'),
    ]);
    expect(choices.map((item) => item.friendlyName), [
      'Example drug 5 mg tablet',
      'Example drug 5 mg tablet (option 2)',
    ]);
    expect(choices.any((item) => item.friendlyName.contains('RxCUI')), isFalse);
  });
}
