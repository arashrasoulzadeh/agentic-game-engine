import 'dart:math' as math;

/// `10^e` as a double. `math.pow(10, e)` with two ints is *integer* arithmetic in Dart and wraps to 0
/// past 1e18, which silently broke every value above that; the base must be a double.
const double _quantum = 1e14;

double _pow10(int e) => math.pow(10.0, e).toDouble();

/// A real number with a huge range and ~15 significant digits, for
/// incremental games whose totals outgrow a 64-bit integer (and whose `double` loses meaning past
/// 1e308).
///
/// Stored as `mantissa * 10^exponent` with `1 <= |mantissa| < 10` (or exactly zero), so the range is
/// about 1e±(9e15) and arithmetic never overflows. The price is precision: like a `double`, it keeps
/// roughly 15 digits, so adding a tiny number to a huge one changes nothing - which is the behaviour
/// an idle game wants, and is stated here so nobody uses it for money. Values with an exponent of 15 or
/// more are treated as whole numbers.
///
/// Immutable; deterministic across platforms for the same operation order (it is plain `double`
/// arithmetic plus `pow`/`log`, so results may differ in the last bit between platforms' `pow`; compare
/// with [approxEquals] in tests, not `==`, after chains of `pow`).
class BigNumber implements Comparable<BigNumber> {
  const BigNumber._(this._mantissa, this._exponent);

  final double _mantissa;
  final int _exponent;

  /// Zero.
  static const BigNumber zero = BigNumber._(0, 0);

  /// One.
  static const BigNumber one = BigNumber._(1, 0);

  /// The value of [value], which may be any finite `double` (or an `int`). `NaN` and infinities are
  /// rejected: a game value that became one has a bug that should surface, not spread.
  factory BigNumber.from(num value) {
    final d = value.toDouble();
    if (d.isNaN || d.isInfinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    return _normalize(d, 0);
  }

  /// `mantissa * 10^exponent`, normalised.
  factory BigNumber.fromParts(double mantissa, int exponent) {
    if (mantissa.isNaN || mantissa.isInfinite) {
      throw ArgumentError.value(mantissa, 'mantissa', 'must be finite');
    }
    return _normalize(mantissa, exponent);
  }

  /// Parses `123`, `-4.5`, `1.5e300`, `2E-7`. Throws [FormatException] otherwise.
  factory BigNumber.parse(String text) {
    final t = text.trim();
    final m = RegExp(
      r'^([+-]?(?:\d+\.?\d*|\.\d+))(?:[eE]([+-]?\d+))?$',
    ).firstMatch(t);
    if (m == null) throw FormatException('Not a number', text);
    final mant = double.parse(m.group(1)!);
    final exp = m.group(2) == null ? 0 : int.parse(m.group(2)!);
    return _normalize(mant, exp);
  }

  static BigNumber _normalize(double mantissa, int exponent) {
    if (mantissa == 0) return zero;
    final shift = (math.log(mantissa.abs()) / math.ln10).floor();
    // Scale by a *positive* power of ten whenever possible: 10^n is exact as a double up to n = 22,
    // while 10^-n is not, and dividing by 0.1 turned 0.99 into 9.899999999999999.
    var m = shift >= 0 ? mantissa / _pow10(shift) : mantissa * _pow10(-shift);
    var e = exponent + shift;
    // log10 rounding can leave m just outside [1, 10); correct it.
    if (m.abs() >= 10) {
      m /= 10;
      e++;
    } else if (m.abs() < 1) {
      m *= 10;
      e--;
    }
    // Quantise to 14 decimal places. Without it, binary noise accumulates: 9.8 - 0.1 is
    // 9.700000000000001, and a wallet drained by repeated purchases ends up a hair off zero, so an
    // exactly affordable price is refused. Rounding to the digits the type promises removes the noise
    // while leaving every genuine digit alone.
    m = (m * _quantum).roundToDouble() / _quantum;
    if (m.abs() >= 10) {
      m /= 10;
      e++;
    }
    return BigNumber._(m, e);
  }

  /// True for exactly zero.
  bool get isZero => _mantissa == 0;

  /// True for values below zero.
  bool get isNegative => _mantissa < 0;

  /// The mantissa, `1 <= |m| < 10`, or 0.
  double get mantissa => _mantissa;

  /// The power of ten.
  int get exponent => _exponent;

  /// This value as a `double`, or +/- infinity when it does not fit.
  double toDouble() {
    if (isZero) return 0;
    if (_exponent > 308)
      return _mantissa.isNegative ? double.negativeInfinity : double.infinity;
    if (_exponent < -323) return 0;
    return _exponent >= 0
        ? _mantissa * _pow10(_exponent)
        : _mantissa / _pow10(-_exponent);
  }

  /// The absolute value.
  BigNumber abs() => isNegative ? -this : this;

  /// The negation.
  BigNumber operator -() => isZero ? this : BigNumber._(-_mantissa, _exponent);

  /// Sum. A term more than 17 orders of magnitude smaller than the other is lost, as in a `double`.
  BigNumber operator +(BigNumber other) {
    if (isZero) return other;
    if (other.isZero) return this;
    final big = _exponent >= other._exponent ? this : other;
    final small = identical(big, this) ? other : this;
    final diff = big._exponent - small._exponent;
    if (diff > 17) return big;
    return _normalize(
      big._mantissa + small._mantissa / _pow10(diff),
      big._exponent,
    );
  }

  /// Difference.
  BigNumber operator -(BigNumber other) => this + (-other);

  /// Product.
  BigNumber operator *(BigNumber other) {
    if (isZero || other.isZero) return zero;
    return _normalize(_mantissa * other._mantissa, _exponent + other._exponent);
  }

  /// Quotient. Throws an [ArgumentError] when dividing by zero.
  BigNumber operator /(BigNumber other) {
    if (other.isZero) throw ArgumentError('Division by zero');
    if (isZero) return zero;
    return _normalize(_mantissa / other._mantissa, _exponent - other._exponent);
  }

  /// `this` raised to [power]. A negative base needs an integer power. `0^0` is 1.
  BigNumber pow(num power) {
    final p = power.toDouble();
    if (p == 0) return one;
    if (isZero) return zero;
    if (isNegative && p != p.roundToDouble()) {
      throw ArgumentError('Negative base needs an integer power');
    }
    final negative = isNegative && p.round().isOdd;
    final logValue = (math.log(_mantissa.abs()) / math.ln10 + _exponent) * p;
    final e = logValue.floor();
    final m = math.pow(10.0, logValue - e).toDouble();
    final result = _normalize(m, e);
    return negative ? -result : result;
  }

  /// The square root of a non-negative value.
  BigNumber sqrt() {
    if (isNegative) throw ArgumentError('Square root of a negative number');
    return pow(0.5);
  }

  /// Base-10 logarithm of a positive value.
  double log10() {
    if (_mantissa <= 0) throw ArgumentError('log10 needs a positive number');
    return math.log(_mantissa) / math.ln10 + _exponent;
  }

  /// The largest whole number not above this. Values with an exponent >= 15 are already whole.
  BigNumber floor() {
    if (_exponent >= 15) return this;
    if (_exponent < 0) return isNegative ? BigNumber.from(-1) : zero;
    return BigNumber.from(toDouble().floorToDouble());
  }

  /// Whichever is larger.
  static BigNumber max(BigNumber a, BigNumber b) => a >= b ? a : b;

  /// Whichever is smaller.
  static BigNumber min(BigNumber a, BigNumber b) => a <= b ? a : b;

  /// Total order: negative, zero, positive; larger exponent wins within a sign.
  @override
  int compareTo(BigNumber other) {
    if (isZero && other.isZero) return 0;
    if (isNegative != other.isNegative || isZero || other.isZero) {
      final a = isZero ? 0 : (isNegative ? -1 : 1);
      final b = other.isZero ? 0 : (other.isNegative ? -1 : 1);
      return a.compareTo(b);
    }
    final sign = isNegative ? -1 : 1;
    if (_exponent != other._exponent)
      return sign * _exponent.compareTo(other._exponent);
    return _mantissa.compareTo(other._mantissa);
  }

  /// Greater than.
  bool operator >(BigNumber other) => compareTo(other) > 0;

  /// Greater than or equal.
  bool operator >=(BigNumber other) => compareTo(other) >= 0;

  /// Less than.
  bool operator <(BigNumber other) => compareTo(other) < 0;

  /// Less than or equal.
  bool operator <=(BigNumber other) => compareTo(other) <= 0;

  /// Whether the two agree to within [relative] of the larger magnitude (default 1e-12, a few digits
  /// inside the 15 this type keeps). Use after chains of arithmetic; `==` is exact.
  bool approxEquals(BigNumber other, {double relative = 1e-12}) {
    if (this == other) return true;
    if (isZero || other.isZero) return false;
    if (isNegative != other.isNegative) return false;
    final diff = (abs() - other.abs()).abs();
    return diff <= BigNumber.max(abs(), other.abs()) * BigNumber.from(relative);
  }

  @override
  bool operator ==(Object other) =>
      other is BigNumber &&
      other._mantissa == _mantissa &&
      other._exponent == _exponent;

  @override
  int get hashCode => Object.hash(_mantissa, _exponent);

  /// `1.5e300`, or the plain number when it is small and whole-ish (for logs and tests; use the
  /// formatting helpers for players).
  @override
  String toString() {
    if (isZero) return '0';
    if (_exponent.abs() < 6) {
      final d = toDouble();
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return '${_mantissa}e$_exponent';
  }

  /// JSON as a string, `1.5e300`: exact for the stored parts and readable in a save file.
  String toJson() => isZero ? '0' : '${_mantissa}e$_exponent';

  /// The reverse of [toJson]; also accepts a plain JSON number.
  factory BigNumber.fromJson(Object json) {
    if (json is num) return BigNumber.from(json);
    return BigNumber.parse(json as String);
  }
}
