import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every mode has a 4x5 matrix whose colour rows each sum to 1, so white stays white',
    () {
      for (final mode in ['protanopia', 'deuteranopia', 'tritanopia']) {
        final m = colorblindMatrix(mode)!;
        expect(m.length, 20, reason: mode);
        for (var row = 0; row < 3; row++) {
          final sum = m[row * 5] + m[row * 5 + 1] + m[row * 5 + 2];
          expect(sum, closeTo(1, 1e-9), reason: '$mode row $row');
        }
        expect(m.sublist(15), [0, 0, 0, 1, 0], reason: 'alpha is untouched');
      }
    },
  );

  test('none and unknown modes simulate nothing', () {
    expect(colorblindMatrix('none'), isNull);
    expect(colorblindMatrix('plaid'), isNull);
  });

  test('the modes really differ, and protanopia loses red/green contrast', () {
    final p = colorblindMatrix('protanopia')!;
    final d = colorblindMatrix('deuteranopia')!;
    expect(p, isNot(d));
    // Pure red and pure green map to nearly the same red output channel.
    final redOut = p[0];
    final greenOut = p[1];
    expect((redOut - greenOut).abs(), lessThan(0.2));
  });

  testWidgets('colorblindFiltered wraps only when a mode is active', (
    tester,
  ) async {
    const child = SizedBox(key: Key('c'));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: colorblindFiltered('none', child),
      ),
    );
    expect(find.byType(ColorFiltered), findsNothing);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: colorblindFiltered('tritanopia', child),
      ),
    );
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(find.byKey(const Key('c')), findsOneWidget);
  });
}
