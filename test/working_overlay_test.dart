import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/widgets/working_overlay.dart';

void main() {
  testWidgets('working overlay shows progress and blocks the screen',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SizedBox.expand(
                child: TextButton(
                  onPressed: () => tapped = true,
                  child: const Text('Add item'),
                ),
              ),
              const WorkingOverlay(message: 'Saving your information...'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving your information...'), findsOneWidget);

    await tester.tap(find.text('Add item'), warnIfMissed: false);
    expect(tapped, isFalse);
  });
}
