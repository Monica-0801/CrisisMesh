import 'package:flutter_test/flutter_test.dart';

import 'package:crisismesh_flutter/main.dart';

void main() {
  testWidgets('One tap on SOS activates emergency capture', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CrisisMeshApp());

    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('EMERGENCY DETAILS'), findsNothing);

    final sosFinder = find.text('SOS');
    await tester.tap(sosFinder);
    await tester.pumpAndSettle();

    expect(find.text('SOS ACTIVE'), findsOneWidget);
    expect(find.text('EMERGENCY DETAILS'), findsOneWidget);
    expect(find.text('Voice capture is preparing'), findsOneWidget);
    expect(find.text('CAPTURE VOICE'), findsNothing);
    expect(find.text('PHOTO'), findsNothing);
  });
}
