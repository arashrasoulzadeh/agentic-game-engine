import 'package:flutter_test/flutter_test.dart';

import 'package:game_agent/main.dart';

void main() {
  testWidgets('stress test screen renders entity count controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const StressTestApp());
    await tester.pump();

    expect(find.text('200'), findsOneWidget);
    expect(find.text('10000'), findsOneWidget);
  });
}
