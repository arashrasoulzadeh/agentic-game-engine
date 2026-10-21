import 'big_number.dart';

/// How [formatBigNumber] writes a number.
enum NumberStyle {
  /// `1.23K`, `4.50M`, `7.89B`, ... named up to decillion, then scientific.
  suffix,

  /// `1.23e45`.
  scientific,

  /// Like scientific but the exponent is a multiple of three: `123e45`, matching the suffix groups.
  engineering,
}

const _suffixes = [
  '',
  'K',
  'M',
  'B',
  'T',
  'Qa',
  'Qi',
  'Sx',
  'Sp',
  'Oc',
  'No',
  'Dc',
];

/// Writes [value] for a player.
///
/// - Below 1000 the number is shown plainly: whole numbers without a decimal point, otherwise with up
///   to [decimals] places and no trailing zeros (`12`, `0.5`, `3.14`).
/// - At 1000 and above, [style] decides (see [NumberStyle]); the mantissa always has exactly
///   [decimals] places (`1.00K`), which keeps columns of numbers aligned.
/// - Rounding carries: 999,999 is `1.00M`, not `1000.00K`.
/// - [decimalSeparator] replaces the `.`; pass the locale's (for example `,`).
/// - Negatives get a leading `-`.
String formatBigNumber(
  BigNumber value, {
  NumberStyle style = NumberStyle.suffix,
  int decimals = 2,
  String decimalSeparator = '.',
}) {
  if (decimals < 0)
    throw ArgumentError.value(decimals, 'decimals', 'must not be negative');
  if (value.isZero) return '0';
  final sign = value.isNegative ? '-' : '';
  final abs = value.abs();

  String swap(String s) =>
      decimalSeparator == '.' ? s : s.replaceFirst('.', decimalSeparator);

  if (abs < BigNumber.from(1000)) {
    final d = abs.toDouble();
    var text = d.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    // 999.999 rounds to "1000" at two decimals: that belongs to the next group, not here.
    if (text == '1000') return '$sign${swap(_group(abs, 1, decimals, style))}';
    return '$sign${swap(text)}';
  }

  switch (style) {
    case NumberStyle.suffix:
      final group = abs.exponent ~/ 3;
      return '$sign${swap(_group(abs, group, decimals, style))}';
    case NumberStyle.scientific:
      var m = abs.mantissa;
      var e = abs.exponent;
      var text = m.toStringAsFixed(decimals);
      if (double.parse(text) >= 10) {
        m /= 10;
        e++;
        text = m.toStringAsFixed(decimals);
      }
      return '$sign${swap(text)}e$e';
    case NumberStyle.engineering:
      final e = abs.exponent - abs.exponent % 3;
      var m = abs.mantissa * _p10(abs.exponent - e);
      var text = m.toStringAsFixed(decimals);
      var exp = e;
      if (double.parse(text) >= 1000) {
        m /= 1000;
        exp += 3;
        text = m.toStringAsFixed(decimals);
      }
      return '$sign${swap(text)}e$exp';
  }
}

/// The value as `x.xx` plus the suffix for 1000^[group], carrying into the next group when rounding
/// reaches 1000, and falling back to scientific past the named suffixes.
String _group(BigNumber abs, int group, int decimals, NumberStyle style) {
  if (group >= _suffixes.length) {
    return formatBigNumber(
      abs,
      style: NumberStyle.scientific,
      decimals: decimals,
    );
  }
  var scaled = abs.mantissa * _p10(abs.exponent - group * 3);
  var text = scaled.toStringAsFixed(decimals);
  if (double.parse(text) >= 1000) {
    group++;
    if (group >= _suffixes.length) {
      return formatBigNumber(
        abs,
        style: NumberStyle.scientific,
        decimals: decimals,
      );
    }
    scaled /= 1000;
    text = scaled.toStringAsFixed(decimals);
  }
  return '$text${_suffixes[group]}';
}

double _p10(int e) {
  var r = 1.0;
  final n = e.abs();
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return e < 0 ? 1 / r : r;
}
