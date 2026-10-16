import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/widgets/label_sides_review_screen.dart';

Future<LabelSidesAction?> _openAndTap(
  WidgetTester tester, {
  required int sides,
  Key? tap,
  bool pressBack = false,
}) async {
  LabelSidesAction? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => FilledButton(
        onPressed: () async {
          result = await Navigator.push<LabelSidesAction>(
            context,
            MaterialPageRoute(
              builder: (_) => LabelSidesReviewScreen(
                imagePaths: List.filled(sides, 'missing.jpg'),
              ),
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (pressBack) {
    await tester.pageBack();
  } else {
    await tester.tap(find.byKey(tap!));
  }
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('Add Another Side and Done return their actions', (tester) async {
    expect(
      await _openAndTap(tester, sides: 1, tap: const Key('label-sides-add')),
      LabelSidesAction.addSide,
    );
    expect(
      await _openAndTap(tester, sides: 2, tap: const Key('label-sides-done')),
      LabelSidesAction.done,
    );
  });

  testWidgets('no Add Another Side after the last allowed side', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LabelSidesReviewScreen(imagePaths: List.filled(4, 'missing.jpg')),
    ));
    expect(find.byKey(const Key('label-sides-add')), findsNothing);
    expect(find.text('4 sides scanned'), findsOneWidget);
  });

  testWidgets('Back cancels instead of returning nothing', (tester) async {
    expect(
      await _openAndTap(tester, sides: 1, pressBack: true),
      LabelSidesAction.cancel,
    );
  });
}
