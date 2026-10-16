import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/screens/meds_screen.dart';
import 'package:vitalink/services/drug_lookup_service.dart';
import 'package:vitalink/widgets/medication_drug_review_screen.dart';

const _methocarbamol = DrugProduct(
  rxcui: '197943',
  rxNormName: 'methocarbamol 500 MG Oral Tablet',
  strength: '500 MG',
  form: 'Oral Tablet',
  drugType: 'generic',
  ndc: '00000-0000-00',
  ndcSource: 'representative',
);

class FakeDrugLookup implements DrugLookupApi {
  FakeDrugLookup({
    this.verification = const DrugVerificationResult.noMatch(),
    this.searchResult = const DrugSearchResult.available(['methocarbamol']),
    this.strengthResult =
        const DrugOptionsResult.available([_methocarbamol]),
    this.selectResult =
        const DrugVerificationResult.sure(_methocarbamol),
  });

  DrugVerificationResult verification;
  DrugSearchResult searchResult;
  DrugOptionsResult strengthResult;
  DrugVerificationResult selectResult;

  @override
  Future<DrugVerificationResult> verify({
    required String name,
    required String dose,
    String form = '',
    String ndc = '',
  }) async =>
      verification;

  @override
  Future<DrugSearchResult> search(String text) async => searchResult;

  @override
  Future<DrugOptionsResult> strengths(String drug) async => strengthResult;

  @override
  Future<DrugVerificationResult> select(String rxcui) async => selectResult;
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.lookup,
    this.current = 1,
    this.total = 1,
    this.imagePaths = const [],
  });

  final DrugLookupApi lookup;
  final int current;
  final int total;
  final List<String> imagePaths;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Medication? result;

  Future<void> open() async {
    result = await Navigator.push<Medication>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationDrugReviewScreen(
          medication: Medication(
            name: 'Methocarbamol',
            dose: '500 mg',
            frequency: 'twice daily',
            quantity: '60',
            prescriber: 'Main Pharmacy\n555-0100',
            daysSupply: 30,
            refills: '2',
          ),
          lookup: widget.lookup,
          imagePaths: widget.imagePaths,
          current: widget.current,
          total: widget.total,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            FilledButton(onPressed: open, child: const Text('Open review')),
            if (result != null)
              Text(
                '${result!.name}|${result!.dose}|${result!.rxcui}|'
                '${result!.matchStatus}|${result!.frequency}|'
                '${result!.daysSupply}|${result!.refills}',
                key: const Key('result'),
              ),
          ],
        ),
      );
}

Future<void> _open(WidgetTester tester, FakeDrugLookup lookup,
    {int current = 1, int total = 1, List<String> imagePaths = const []}) async {
  await tester.pumpWidget(MaterialApp(
    home: _Harness(
      lookup: lookup,
      current: current,
      total: total,
      imagePaths: imagePaths,
    ),
  ));
  await tester.tap(find.text('Open review'));
  await tester.pumpAndSettle();
}

void main() {
  test('copyWith preserves every drug matching field', () {
    final original = Medication(
      name: 'Eliquis',
      dose: '5 mg tablet',
      rxcui: '1364447',
      ndc: '00003-0894-21',
      ndcSource: 'label',
      drugForm: 'Oral Tablet',
      drugType: 'brand',
      daysSupply: 30,
      refills: '2',
      matchStatus: 'confirmed',
    );
    final edited = original.copyWith(frequency: 'twice daily');
    expect(edited.rxcui, original.rxcui);
    expect(edited.ndc, original.ndc);
    expect(edited.ndcSource, original.ndcSource);
    expect(edited.drugForm, original.drugForm);
    expect(edited.drugType, original.drugType);
    expect(edited.daysSupply, original.daysSupply);
    expect(edited.refills, original.refills);
    expect(edited.matchStatus, original.matchStatus);
  });

  testWidgets('sure then Yes saves codes and keeps scanned details',
      (tester) async {
    await _open(
      tester,
      FakeDrugLookup(
        verification:
            const DrugVerificationResult.sure(_methocarbamol),
      ),
    );
    expect(find.text('Is this your medicine?'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'Methocarbamol|500 mg tablet|197943|confirmed|twice daily|30|2'),
      findsOneWidget,
    );
  });

  testWidgets('sure then No opens search with an empty box', (tester) async {
    await _open(
      tester,
      FakeDrugLookup(
        verification:
            const DrugVerificationResult.sure(_methocarbamol),
      ),
    );
    await tester.tap(find.text('No'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('drug-search-field')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('no match opens search with an empty box', (tester) async {
    await _open(tester, FakeDrugLookup());
    final field = tester.widget<TextField>(find.byKey(const Key('drug-search-field')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('search then strength then select saves confirmed',
      (tester) async {
    await _open(tester, FakeDrugLookup());
    await tester.enterText(
      find.byKey(const Key('drug-search-field')),
      'metho',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Methocarbamol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Methocarbamol 500 mg tablet'));
    await tester.pumpAndSettle();
    expect(find.textContaining('|197943|confirmed|'), findsOneWidget);
  });

  testWidgets('Skip for now saves the scanned medicine as unmatched',
      (tester) async {
    await _open(tester, FakeDrugLookup());
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Methocarbamol|500 mg||unmatched|'),
        findsOneWidget);
  });

  testWidgets('unavailable explains the problem and saves unmatched',
      (tester) async {
    await _open(
      tester,
      FakeDrugLookup(
        verification: const DrugVerificationResult.unavailable(),
      ),
    );
    expect(find.textContaining("We couldn't check this medicine right now"),
        findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Methocarbamol|500 mg||unmatched|'),
        findsOneWidget);
  });

  testWidgets('multi-med review shows the current medicine number',
      (tester) async {
    await _open(tester, FakeDrugLookup(), current: 2, total: 5);
    expect(find.text('Medicine 2 of 5'), findsOneWidget);
  });

  testWidgets('Back from No-search returns to confirmation', (tester) async {
    await _open(
      tester,
      FakeDrugLookup(
        verification: const DrugVerificationResult.sure(_methocarbamol),
      ),
    );
    await tester.tap(find.text('No'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Is this your medicine?'), findsOneWidget);
  });

  testWidgets('Back from initial search requires Keep checking or Skip it',
      (tester) async {
    await _open(tester, FakeDrugLookup());
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Stop checking this medicine?'), findsOneWidget);
    await tester.tap(find.text('Keep checking'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drug-search-field')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('|unmatched|'), findsOneWidget);
  });

  testWidgets('strengths Back and Search again both return to search',
      (tester) async {
    await _open(tester, FakeDrugLookup());
    await tester.enterText(find.byKey(const Key('drug-search-field')), 'metho');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Methocarbamol'));
    await tester.pumpAndSettle();
    expect(find.text('Search again'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drug-search-field')), findsOneWidget);
  });

  testWidgets('empty strengths explains the result and offers Search again',
      (tester) async {
    final lookup = FakeDrugLookup(
      strengthResult: const DrugOptionsResult.available([]),
    );
    await _open(tester, lookup);
    await tester.enterText(find.byKey(const Key('drug-search-field')), 'metho');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Methocarbamol'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No strengths found'), findsOneWidget);
    await tester.tap(find.text('Search again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drug-search-field')), findsOneWidget);
  });

  testWidgets('search results normalize RxNav tall-man lettering',
      (tester) async {
    final lookup = FakeDrugLookup(
      searchResult: const DrugSearchResult.available([
        'metFORMIN',
        'hydroCHLOROthiazide / lisinopril',
      ]),
    );
    await _open(tester, lookup);
    await tester.enterText(find.byKey(const Key('drug-search-field')), 'me');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Hydrochlorothiazide / Lisinopril'), findsOneWidget);
  });

  testWidgets('failed search retries on the same screen', (tester) async {
    final lookup = FakeDrugLookup(
      searchResult: const DrugSearchResult.unavailable(),
    );
    await _open(tester, lookup);
    await tester.enterText(find.byKey(const Key('drug-search-field')), 'metho');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.text("We couldn't reach the medicine list."), findsOneWidget);
    lookup.searchResult =
        const DrugSearchResult.available(['methocarbamol']);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Methocarbamol'), findsOneWidget);
  });

  testWidgets('failed strengths retries on the same screen', (tester) async {
    final lookup = FakeDrugLookup(
      strengthResult: const DrugOptionsResult.unavailable(),
    );
    await _open(tester, lookup);
    await tester.enterText(find.byKey(const Key('drug-search-field')), 'metho');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Methocarbamol'));
    await tester.pumpAndSettle();
    expect(find.text("We couldn't reach the medicine list."), findsOneWidget);
    lookup.strengthResult =
        const DrugOptionsResult.available([_methocarbamol]);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Methocarbamol 500 mg tablet'), findsOneWidget);
  });

  test('search photo becomes a compact strip while the keyboard is open', () {
    expect(medicationLabelPhotoHeight(800, search: true), 320);
    expect(medicationLabelPhotoHeight(450, search: true), 180);
    expect(
      medicationLabelPhotoHeight(
        450,
        search: true,
        keyboardOpen: true,
      ),
      80,
    );
    expect(medicationLabelPhotoHeight(800, search: false), 150);
  });

  for (final size in [const Size(410, 890), const Size(360, 640)]) {
    testWidgets(
      'search fits with keyboard and large text at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);

        final image = File(
          '${Directory.systemTemp.path}\\vitalink-label-${size.width.toInt()}.png',
        );
        image.writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ));
        addTearDown(() {
          if (image.existsSync()) image.deleteSync();
        });

        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: MedicationDrugReviewScreen(
            medication: Medication(
              name: 'Guanfacine ER',
              dose: '2 mg',
            ),
            lookup: FakeDrugLookup(),
            imagePaths: [image.path],
            current: 1,
            total: 1,
          ),
        ));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 380);
        await tester.pumpAndSettle();

        final layoutException = tester.takeException();
        expect(layoutException, isNull);
        expect(find.byKey(const Key('drug-search-field')), findsOneWidget);
        expect(find.byKey(const Key('drug-search-scroll')), findsOneWidget);
        expect(find.byKey(const Key('keyboard-skip-medicine')), findsOneWidget);
      },
    );
  }

  test('identity edits clear stale drug codes and unchanged edits keep them', () {
    final confirmed = Medication(
      name: 'Eliquis',
      dose: '5 mg tablet',
      rxcui: '1364447',
      ndc: '00003-0894-21',
      ndcSource: 'label',
      drugForm: 'Oral Tablet',
      drugType: 'brand',
      matchStatus: 'confirmed',
    );
    final unchanged = medicationAfterIdentityEdit(
      confirmed,
      'Eliquis',
      '5 mg tablet',
    );
    expect(unchanged.rxcui, '1364447');
    final changed = medicationAfterIdentityEdit(
      confirmed,
      'Eliquis',
      '2.5 mg tablet',
    );
    expect(changed.rxcui, isEmpty);
    expect(changed.ndc, isEmpty);
    expect(changed.ndcSource, isEmpty);
    expect(changed.drugForm, isEmpty);
    expect(changed.drugType, isEmpty);
    expect(changed.matchStatus, 'unmatched');
  });

  test('changed pharmacy text clears every pharmacy verification field', () {
    final medication = Medication(
      prescriber: 'Old Pharmacy',
      pharmacyNpi: '1234567890',
      pharmacyVerificationStatus: 'verified',
      pharmacyNpiCandidates: [
        {'npi': '1234567890'},
      ],
      pharmacyVerifiedAt: DateTime(2026),
      pharmacyVerifiedBy: 'nppes',
    );
    expect(pharmacyTextChanged(medication.prescriber, 'New Pharmacy'), isTrue);
    resetPharmacyVerification(medication);
    expect(medication.pharmacyNpi, isNull);
    expect(medication.pharmacyVerificationStatus, 'unverified');
    expect(medication.pharmacyNpiCandidates, isEmpty);
    expect(medication.pharmacyVerifiedAt, isNull);
    expect(medication.pharmacyVerifiedBy, isNull);
    expect(pharmacyTextChanged('Same Pharmacy', ' same pharmacy '), isFalse);
  });
}
