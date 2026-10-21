import 'dart:convert';
import 'dart:math';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

BigNumber n(String s) => BigNumber.parse(s);

/// The slow, obviously-correct answer: sum the next prices one at a time.
BigNumber slowTotal(CostCurve c, int owned, int count) {
  var t = BigNumber.zero;
  for (var i = 0; i < count; i++) {
    t = t + c.costOfNext(owned + i);
  }
  return t;
}

int slowMax(CostCurve c, int owned, BigNumber budget, {int cap = 5000}) {
  var spent = BigNumber.zero;
  var k = 0;
  while (k < cap) {
    final next = spent + c.costOfNext(owned + k);
    if (next > budget) break;
    spent = next;
    k++;
  }
  return k;
}

void main() {
  group('TableCost', () {
    BigNumber n(String s) => BigNumber.parse(s);
    final table = TableCost(prices: [n('10'), n('20'), n('50')], tailGrowth: 2);

    test('prices come from the table, then grow by tailGrowth', () {
      expect(table.costOfNext(0), n('10'));
      expect(table.costOfNext(2), n('50'));
      expect(table.costOfNext(3), n('100'));
      expect(table.costOfNext(4), n('200'));
    });

    test('totalCost and maxAffordable match the one-by-one answer', () {
      for (final owned in [0, 1, 3, 5]) {
        for (final count in [0, 1, 2, 4, 7]) {
          expect(
            table
                .totalCost(owned, count)
                .approxEquals(slowTotal(table, owned, count)),
            isTrue,
            reason: 'owned $owned count $count',
          );
        }
        for (final b in ['5', '10', '29', '80', '1000', '123456']) {
          expect(
            table.maxAffordable(owned, n(b)),
            slowMax(table, owned, n(b)),
            reason: 'owned $owned budget $b',
          );
        }
      }
    });

    test('tailGrowth 1 repeats the last price', () {
      final flat = TableCost(prices: [n('5'), n('7')]);
      expect(flat.costOfNext(9), n('7'));
      expect(flat.totalCost(1, 3), n('21'));
    });

    test('round-trips through JSON', () {
      final back = CostCurve.fromJson(
        (jsonDecode(jsonEncode(table.toJson())) as Map).cast<String, dynamic>(),
      );
      expect(back, isA<TableCost>());
      expect(back.costOfNext(4), n('200'));
    });
  });

  group('GeometricCost', () {
    final curve = GeometricCost(base: n('10'), growth: 1.15);

    test('each unit costs growth times the last', () {
      expect(curve.costOfNext(0), n('10'));
      expect(curve.costOfNext(1).approxEquals(n('11.5')), isTrue);
      expect(
        curve.costOfNext(10).approxEquals(n('40.4555774'), relative: 1e-7),
        isTrue,
      );
    });

    test('the closed-form total equals summing one at a time', () {
      for (final owned in [0, 1, 7, 50, 300]) {
        for (final count in [1, 2, 10, 100]) {
          expect(
            curve
                .totalCost(owned, count)
                .approxEquals(slowTotal(curve, owned, count), relative: 1e-9),
            isTrue,
            reason: 'owned $owned count $count',
          );
        }
      }
      expect(curve.totalCost(5, 0), BigNumber.zero);
    });

    test('maxAffordable matches a brute-force count and never overspends', () {
      final rng = Random(5);
      for (var i = 0; i < 200; i++) {
        final owned = rng.nextInt(200);
        final budget = BigNumber.fromParts(
          1 + rng.nextDouble() * 9,
          rng.nextInt(12),
        );
        final fast = curve.maxAffordable(owned, budget);
        expect(
          fast,
          slowMax(curve, owned, budget),
          reason: 'owned $owned budget $budget',
        );
        expect(curve.totalCost(owned, fast) <= budget, isTrue);
        expect(curve.totalCost(owned, fast + 1) > budget, isTrue);
      }
    });

    test('a huge budget is answered without looping (1e200 coins)', () {
      final big = GeometricCost(base: n('1'), growth: 1.07);
      final k = big.maxAffordable(0, n('1e200'));
      expect(k, greaterThan(6000));
      expect(big.totalCost(0, k) <= n('1e200'), isTrue);
      expect(big.totalCost(0, k + 1) > n('1e200'), isTrue);
    });

    test('cannot afford one: zero; the limit caps the answer', () {
      expect(curve.maxAffordable(0, n('9.99')), 0);
      expect(curve.maxAffordable(0, n('1e30'), limit: 10), 10);
      expect(curve.maxAffordable(0, n('1e30'), limit: 0), 0);
    });

    test('growth 1 degenerates to a flat price', () {
      final flat = GeometricCost(base: n('25'), growth: 1);
      expect(flat.totalCost(40, 4), n('100'));
      expect(flat.maxAffordable(40, n('260')), 10);
    });
  });

  group('LinearCost', () {
    final curve = LinearCost(base: n('100'), step: n('50'));

    test('the price rises by a fixed step', () {
      expect(curve.costOfNext(0), n('100'));
      expect(curve.costOfNext(4), n('300'));
    });

    test(
      'the closed-form total equals summing, and maxAffordable matches brute force',
      () {
        for (final owned in [0, 3, 40]) {
          for (final count in [1, 5, 60]) {
            expect(
              curve
                  .totalCost(owned, count)
                  .approxEquals(slowTotal(curve, owned, count)),
              isTrue,
            );
          }
        }
        final rng = Random(8);
        for (var i = 0; i < 200; i++) {
          final owned = rng.nextInt(100);
          final budget = BigNumber.from(rng.nextInt(2000000));
          expect(
            curve.maxAffordable(owned, budget),
            slowMax(curve, owned, budget),
            reason: 'owned $owned budget $budget',
          );
        }
      },
    );

    test('a zero step is a flat price', () {
      final flat = LinearCost(base: n('10'), step: BigNumber.zero);
      expect(flat.maxAffordable(3, n('95')), 9);
    });
  });

  test('curves round-trip through JSON and unknown types are rejected', () {
    for (final c in <CostCurve>[
      GeometricCost(base: n('15'), growth: 1.1),
      LinearCost(base: n('5'), step: n('2')),
    ]) {
      final back = CostCurve.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
      );
      expect(back.costOfNext(7), c.costOfNext(7));
      expect(back.runtimeType, c.runtimeType);
    }
    expect(() => CostCurve.fromJson({'type': 'zigzag'}), throwsFormatException);
  });
}
