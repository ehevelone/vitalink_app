import 'package:flutter_test/flutter_test.dart';

import 'package:vitalink/main.dart';

void main() {
  testWidgets('VitaLink app starts on landing screen', (tester) async {
    await tester.pumpWidget(const VitaLinkApp());

    expect(find.text('Welcome To'), findsOneWidget);
  });
}
