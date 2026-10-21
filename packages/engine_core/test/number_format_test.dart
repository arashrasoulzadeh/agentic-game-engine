import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

String f(
  String v, {
  NumberStyle style = NumberStyle.suffix,
  int decimals = 2,
  String sep = '.',
}) => formatBigNumber(
  BigNumber.parse(v),
  style: style,
  decimals: decimals,
  decimalSeparator: sep,
);

void main() {
  group('plain numbers below 1000', () {
    test(
      'whole numbers have no decimal point; fractions drop trailing zeros',
      () {
        expect(f('0'), '0');
        expect(f('7'), '7');
        expect(f('999'), '999');
        expect(f('0.5'), '0.5');
        expect(f('3.14159'), '3.14');
        expect(f('12.30'), '12.3');
        expect(f('0.004'), '0');
      },
    );

    test('negatives keep their sign', () {
      expect(f('-7'), '-7');
      expect(f('-1500'), '-1.50K');
      expect(f('-2.5e12'), '-2.50T');
    });
  });

  group('suffix style', () {
    test('each group of three digits gets its suffix', () {
      expect(f('1000'), '1.00K');
      expect(f('1234'), '1.23K');
      expect(f('45600'), '45.60K');
      expect(f('999000'), '999.00K');
      expect(f('1e6'), '1.00M');
      expect(f('7.89e9'), '7.89B');
      expect(f('1e12'), '1.00T');
      expect(f('1e15'), '1.00Qa');
      expect(f('1e18'), '1.00Qi');
      expect(f('1e33'), '1.00Dc');
    });

    test(
      'rounding carries into the next group instead of printing 1000.00K',
      () {
        expect(f('999999'), '1.00M');
        expect(f('999994'), '999.99K');
        expect(f('999995'), '1.00M');
        expect(f('999.999'), '1.00K');
        expect(f('999999999'), '1.00B');
      },
    );

    test('past the named suffixes it falls back to scientific', () {
      expect(f('1e36'), '1.00e36');
      expect(f('4.5e300'), '4.50e300');
      expect(f('9.999e35'), '999.90Dc');
      expect(
        f('9.99999e35'),
        '1.00e36',
        reason: 'carry out of the last suffix',
      );
    });

    test('decimals are configurable, including none', () {
      expect(f('1234', decimals: 0), '1K');
      expect(f('1234', decimals: 3), '1.234K');
      expect(f('1500', decimals: 1), '1.5K');
      expect(() => f('1', decimals: -1), throwsArgumentError);
    });

    test('the decimal separator can follow the locale', () {
      expect(f('1234', sep: ','), '1,23K');
      expect(f('0.5', sep: ','), '0,5');
      expect(f('1e40', sep: ','), '1,00e40');
    });
  });

  group('scientific style', () {
    test('mantissa and exponent, with rounding carry', () {
      expect(f('1234', style: NumberStyle.scientific), '1.23e3');
      expect(f('9.999e5', style: NumberStyle.scientific), '1.00e6');
      expect(f('1e100', style: NumberStyle.scientific), '1.00e100');
      expect(
        f('5', style: NumberStyle.scientific),
        '5',
        reason: 'small numbers stay plain',
      );
    });
  });

  group('engineering style', () {
    test('the exponent is always a multiple of three', () {
      expect(f('1234', style: NumberStyle.engineering), '1.23e3');
      expect(f('12346', style: NumberStyle.engineering), '12.35e3');
      expect(f('123456', style: NumberStyle.engineering), '123.46e3');
      expect(f('1.5e7', style: NumberStyle.engineering), '15.00e6');
      expect(
        f('9.999999e5', style: NumberStyle.engineering),
        '1.00e6',
        reason: 'carry across the group',
      );
    });
  });
}
