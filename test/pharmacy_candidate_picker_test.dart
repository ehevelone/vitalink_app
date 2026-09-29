import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/widgets/npi_verification_widgets.dart';

void main() {
  testWidgets('pharmacy picker offers another ZIP when there are no matches', (
    tester,
  ) async {
    Map<String, dynamic>? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selection = await showNpiCandidatePicker(
                  context: context,
                  title: 'Which pharmacy is Walgreens?',
                  candidates: const [],
                  allowAlternateZip: true,
                );
              },
              child: const Text('Look up pharmacy'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Look up pharmacy'));
    await tester.pumpAndSettle();
    expect(find.text('Search another ZIP'), findsOneWidget);
    expect(find.textContaining('No matching records here'), findsOneWidget);

    await tester.tap(find.text('Search another ZIP'));
    await tester.pumpAndSettle();
    expect(selection?['_pickerAction'], 'searchAnotherZip');
  });

  testWidgets(
    'mail-order picker shows all ten candidates without local ZIP action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNpiCandidatePicker(
                  context: context,
                  title: 'Which pharmacy is Optum?',
                  candidates: List.generate(
                    10,
                    (index) => {
                      'npi': '${1000000000 + index}',
                      'displayName': 'Mail location ${index + 1}',
                    },
                  ),
                  candidateLimit: 10,
                ),
                child: const Text('Look up mail order'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Look up mail order'));
      await tester.pumpAndSettle();
      expect(find.text('Search another ZIP'), findsNothing);
      expect(find.text('Mail location 10'), findsOneWidget);
    },
  );

  testWidgets('doctor ZIP prompt requires exactly five digits', (tester) async {
    String? selectedZip;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selectedZip = await showDoctorZipPrompt(
                  context: context,
                  doctorName: 'Dr. Smith',
                  registeredZip: '68114',
                );
              },
              child: const Text('Find doctor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Find doctor'));
    await tester.pumpAndSettle();
    expect(find.textContaining('registered ZIP (68114)'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '1234');
    await tester.tap(find.text('Search ZIP'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a 5-digit ZIP code'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '90210');
    await tester.tap(find.text('Search ZIP'));
    await tester.pumpAndSettle();
    expect(selectedZip, '90210');
  });

  testWidgets('pharmacy ZIP prompt closes without a controller exception', (
    tester,
  ) async {
    String? selectedZip;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selectedZip = await showPharmacyZipPrompt(context: context);
              },
              child: const Text('Find pharmacy'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Find pharmacy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '68105');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(selectedZip, '68105');
    expect(tester.takeException(), isNull);
  });

  testWidgets('alternate pharmacy ZIP dialogs hand off without overlap', (
    tester,
  ) async {
    String? selectedZip;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final selection = await showNpiCandidatePicker(
                  context: context,
                  title: 'Which pharmacy is Walgreens?',
                  candidates: const [],
                  allowAlternateZip: true,
                );
                if (selection?['_pickerAction'] != 'searchAnotherZip') return;
                await Future<void>.delayed(const Duration(milliseconds: 250));
                if (!context.mounted) return;
                selectedZip = await showPharmacyZipPrompt(context: context);
              },
              child: const Text('Resolve pharmacy'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Resolve pharmacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search another ZIP'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextFormField), '68105');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(selectedZip, '68105');
    expect(tester.takeException(), isNull);
  });

  testWidgets('doctor ZIP prompt hands off to provider results', (
    tester,
  ) async {
    Map<String, dynamic>? selectedProvider;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final zip = await showDoctorZipPrompt(
                  context: context,
                  doctorName: 'H, Nguyen',
                  registeredZip: '68114',
                );
                if (zip == null) return;
                await Future<void>.delayed(const Duration(milliseconds: 250));
                if (!context.mounted) return;
                selectedProvider = await showNpiCandidatePicker(
                  context: context,
                  title: 'Which provider is H, Nguyen?',
                  candidates: const [
                    {
                      'npi': '1275201147',
                      'displayName': 'HOA THUY NGUYEN',
                      'credential': 'APRN-NP',
                      'taxonomy': 'Nurse Practitioner',
                      'city': 'OMAHA',
                      'state': 'NE',
                      'postalCode': '681051850',
                      'phone': '402-591-4500',
                    },
                  ],
                );
              },
              child: const Text('Resolve doctor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Resolve doctor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '68105');
    await tester.tap(find.text('Search ZIP'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HOA THUY NGUYEN'), findsOneWidget);
    await tester.tap(find.text('HOA THUY NGUYEN'));
    await tester.pumpAndSettle();

    expect(selectedProvider?['npi'], '1275201147');
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider picker can request a more specific ZIP', (
    tester,
  ) async {
    Map<String, dynamic>? pickerResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                pickerResult = await showNpiCandidatePicker(
                  context: context,
                  title: 'Which provider is Smith?',
                  candidates: const [
                    {
                      'npi': '1234567890',
                      'displayName': 'JANE SMITH',
                      'postalCode': '68124',
                      'distanceMiles': 4.2,
                    },
                  ],
                  allowAlternateZip: true,
                );
              },
              child: const Text('Resolve provider'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Resolve provider'));
    await tester.pumpAndSettle();
    expect(find.text('About 4.2 miles away'), findsOneWidget);
    expect(find.text('Search another ZIP'), findsOneWidget);
    await tester.tap(find.text('Search another ZIP'));
    await tester.pumpAndSettle();
    expect(pickerResult?['_pickerAction'], 'searchAnotherZip');
  });
}
