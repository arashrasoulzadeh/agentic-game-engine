import 'dart:convert';
import 'dart:math';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

BigNumber n(String s) => BigNumber.parse(s);

void main() {
  group('construction and normal form', () {
    test('mantissa is always in [1, 10) (or zero), whatever the input', () {
      for (final v in [
        1.0,
        9.999,
        10.0,
        0.5,
        0.0999,
        123456.789,
        1e-7,
        5e300,
        1e15,
      ]) {
        final b = BigNumber.from(v);
        expect(
          b.mantissa.abs(),
          inInclusiveRange(1, 9.999999999999999),
          reason: '$v',
        );
        expect(b.toDouble(), closeTo(v, v.abs() * 1e-12), reason: '$v');
      }
      expect(BigNumber.from(0).isZero, isTrue);
      expect(BigNumber.from(0).mantissa, 0);
    });

    test('equal values are equal however they were built', () {
      expect(BigNumber.from(1500), n('1.5e3'));
      expect(BigNumber.fromParts(15, 2), n('1500'));
      expect(BigNumber.fromParts(0.015, 5), n('1500'));
      expect(BigNumber.from(1500).hashCode, n('1.5e3').hashCode);
    });

    test('NaN and infinity are rejected rather than spread', () {
      expect(() => BigNumber.from(double.nan), throwsArgumentError);
      expect(() => BigNumber.from(double.infinity), throwsArgumentError);
      expect(() => BigNumber.fromParts(double.nan, 0), throwsArgumentError);
    });

    test(
      'parse accepts plain, signed, decimal and exponent forms and rejects junk',
      () {
        expect(n('42').toDouble(), 42);
        expect(n('-4.5').toDouble(), -4.5);
        expect(n('.25').toDouble(), 0.25);
        expect(n('2E-7').toDouble(), closeTo(2e-7, 1e-20));
        expect(n('  1.5e300 ').exponent, 300);
        for (final bad in ['', 'abc', '1e', '1.2.3', '--1', 'e5']) {
          expect(
            () => BigNumber.parse(bad),
            throwsFormatException,
            reason: bad,
          );
        }
      },
    );
  });

  group('ordering', () {
    test('is a total order across signs, zero and magnitudes', () {
      final values = [
        n('-1e50'),
        n('-3'),
        n('-1e-9'),
        BigNumber.zero,
        n('1e-9'),
        n('2'),
        n('9.99'),
        n('10'),
        n('1e50'),
      ];
      for (var i = 0; i < values.length; i++) {
        for (var j = 0; j < values.length; j++) {
          expect(
            values[i].compareTo(values[j]).sign,
            i.compareTo(j).sign,
            reason: '${values[i]} vs ${values[j]}',
          );
        }
      }
      expect(n('2') < n('3'), isTrue);
      expect(n('1e300') > n('9e299'), isTrue);
      expect(n('-1e300') < n('-9e299'), isTrue);
      expect(BigNumber.max(n('1'), n('2')), n('2'));
      expect(BigNumber.min(n('1'), n('2')), n('1'));
    });
  });

  group('arithmetic', () {
    test('basic sums, differences, products, quotients', () {
      expect((n('2') + n('3')), n('5'));
      expect((n('1e20') + n('1e20')), n('2e20'));
      expect((n('5') - n('7')), n('-2'));
      expect((n('3') - n('3')).isZero, isTrue);
      expect((n('1.5e10') * n('2e5')), n('3e15'));
      expect((n('1e300') * n('1e300')), n('1e600'));
      expect((n('9e5') / n('3e2')), n('3e3'));
      expect((n('-6') / n('3')), n('-2'));
      expect(() => n('1') / BigNumber.zero, throwsArgumentError);
    });

    test('the identity elements', () {
      final x = n('7.77e77');
      expect(x + BigNumber.zero, x);
      expect(x * BigNumber.one, x);
      expect(x * BigNumber.zero, BigNumber.zero);
      expect(BigNumber.zero / x, BigNumber.zero);
    });

    test(
      'a term 17+ orders of magnitude smaller than the other is lost, like a double',
      () {
        expect(n('1e30') + n('1'), n('1e30'));
        expect((n('1e30') + n('1')) - n('1e30'), BigNumber.zero);
      },
    );

    test('cancellation near equal values stays well-formed', () {
      final d = n('1.0000000001e5') - n('1e5');
      expect(d.toDouble(), closeTo(1e-5, 1e-9));
      expect(d.mantissa, inInclusiveRange(1, 9.99999));
    });

    test('pow: integer, fractional, huge, negative base', () {
      expect(n('2').pow(10).toDouble(), closeTo(1024, 1e-9));
      expect(n('10').pow(300), n('1e300'));
      expect(
        n('1.07').pow(1000).log10(),
        closeTo(1000 * log(1.07) / ln10, 1e-9),
      );
      expect(n('4').pow(0.5).toDouble(), closeTo(2, 1e-12));
      expect(n('-2').pow(3).toDouble(), closeTo(-8, 1e-12));
      expect(n('-2').pow(2).toDouble(), closeTo(4, 1e-12));
      expect(() => n('-2').pow(0.5), throwsArgumentError);
      expect(n('0').pow(5), BigNumber.zero);
      expect(n('0').pow(0), BigNumber.one);
      expect(n('1e100').sqrt(), n('1e50'));
      expect(() => n('-1').sqrt(), throwsArgumentError);
    });

    test('log10, floor, abs, negation', () {
      expect(n('1e5').log10(), closeTo(5, 1e-12));
      expect(n('3.5e4').log10(), closeTo(4.544068, 1e-6));
      expect(() => BigNumber.zero.log10(), throwsArgumentError);
      expect(n('3.9').floor(), n('3'));
      expect(n('-3.1').floor(), n('-4'));
      expect(n('0.4').floor(), BigNumber.zero);
      expect(n('-0.4').floor(), n('-1'));
      expect(n('1.5e20').floor(), n('1.5e20'));
      expect(n('-7').abs(), n('7'));
      expect(-BigNumber.zero, BigNumber.zero);
    });
  });

  group('properties over a wide range (seeded)', () {
    final rng = Random(42);
    BigNumber random() =>
        BigNumber.fromParts(1 + rng.nextDouble() * 9, rng.nextInt(600) - 300);

    test('a + b - b == a when the magnitudes are comparable', () {
      for (var i = 0; i < 500; i++) {
        final a = random();
        final b = BigNumber.fromParts(
          1 + rng.nextDouble() * 9,
          a.exponent - rng.nextInt(8),
        );
        expect(
          (a + b) - b,
          predicate<BigNumber>((r) => r.approxEquals(a, relative: 1e-9)),
          reason: '$a $b',
        );
      }
    });

    test('a * b / b == a and multiplication commutes', () {
      for (var i = 0; i < 500; i++) {
        final a = random(), b = random();
        expect(
          (a * b) / b,
          predicate<BigNumber>((r) => r.approxEquals(a)),
          reason: '$a $b',
        );
        expect(a * b, b * a);
      }
    });

    test('addition commutes; ordering agrees with subtraction', () {
      for (var i = 0; i < 500; i++) {
        final a = random(), b = random();
        expect(a + b, b + a);
        if (a != b) expect(a > b, (a - b).isNegative == false, reason: '$a $b');
      }
    });

    test(
      'comparison is consistent with the double value where doubles are exact enough',
      () {
        for (var i = 0; i < 500; i++) {
          final x = (rng.nextDouble() - 0.5) * 1e6,
              y = (rng.nextDouble() - 0.5) * 1e6;
          expect(
            BigNumber.from(x).compareTo(BigNumber.from(y)).sign,
            x.compareTo(y).sign,
          );
        }
      },
    );
  });

  group('range and conversion', () {
    test('exponents far beyond double never overflow; toDouble saturates', () {
      final huge = n('1e1000') * n('1e1000');
      expect(huge.exponent, 2000);
      expect(huge.toDouble(), double.infinity);
      expect((-huge).toDouble(), double.negativeInfinity);
      expect(n('1e-1000').toDouble(), 0);
      expect(
        n('1e-1000').isZero,
        isFalse,
        reason: 'still a distinct tiny value',
      );
    });

    test('JSON round-trips bit-identically, including zero and negatives', () {
      for (final v in [
        BigNumber.zero,
        n('1'),
        n('-1.2345678901234567e-250'),
        n('9.999999999999999e300'),
        n('3.14159e1000'),
      ]) {
        final back = BigNumber.fromJson(
          jsonDecode(jsonEncode(v.toJson())) as Object,
        );
        expect(back, v);
        expect(back.mantissa, v.mantissa);
        expect(back.exponent, v.exponent);
      }
      expect(
        BigNumber.fromJson(12),
        n('12'),
        reason: 'a plain JSON number is accepted',
      );
    });

    test('toString is readable', () {
      expect(BigNumber.zero.toString(), '0');
      expect(n('1500').toString(), '1500');
      expect(n('2.5').toString(), '2.5');
      expect(n('1.5e300').toString(), '1.5e300');
    });
  });
}
