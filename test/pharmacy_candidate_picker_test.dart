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
}
