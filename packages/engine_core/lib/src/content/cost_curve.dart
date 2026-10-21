import 'big_number.dart';

/// What the next units of something cost as you own more of it: the engine of an incremental game's
/// pacing. Each curve prices the unit you would buy **next** given how many you [owned] already, and
/// can price a run of units and tell how many a budget affords **without looping** (a budget of 1e200
/// can afford a million units; counting them one by one would not finish).
abstract class CostCurve {
  const CostCurve();

  /// The price of the next single unit when [owned] are already held (`owned >= 0`).
  BigNumber costOfNext(int owned);

  /// The price of buying [count] units in a row starting from [owned].
  BigNumber totalCost(int owned, int count);

  /// The most units (up to [limit]) that [budget] can buy starting from [owned]. Zero if it cannot
  /// afford even one. Exact: it never says a purchase is affordable when [totalCost] exceeds [budget].
  int maxAffordable(int owned, BigNumber budget, {int limit = 1 << 30}) {
    if (limit <= 0 || costOfNext(owned) > budget) return 0;
    var n = _estimate(owned, budget).clamp(0, limit);
    // The closed form is floating point; settle on the exact boundary.
    while (n < limit && totalCost(owned, n + 1) <= budget) {
      n++;
    }
    while (n > 0 && totalCost(owned, n) > budget) {
      n--;
    }
    return n;
  }

  /// A close first guess for [maxAffordable]; it is corrected afterwards, so it may be off by a little.
  int _estimate(int owned, BigNumber budget);

  Map<String, dynamic> toJson();

  /// Reads a curve from its JSON (`{"type": "geometric", ...}`).
  factory CostCurve.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'geometric':
        return GeometricCost(
          base: BigNumber.fromJson(json['base'] as Object),
          growth: (json['growth'] as num).toDouble(),
        );
      case 'linear':
        return LinearCost(
          base: BigNumber.fromJson(json['base'] as Object),
          step: BigNumber.fromJson(json['step'] as Object),
        );
      default:
        throw FormatException('Unknown cost curve type: ${json['type']}');
    }
  }
}

/// `base * growth^owned`: each unit costs [growth] times the last. The classic idle curve; growth
/// 1.07-1.15 is typical.
class GeometricCost extends CostCurve {
  GeometricCost({required this.base, required this.growth})
    : assert(growth >= 1, 'growth below 1 would make units cheaper as you buy');

  final BigNumber base;
  final double growth;

  @override
  BigNumber costOfNext(int owned) => base * BigNumber.from(growth).pow(owned);

  @override
  BigNumber totalCost(int owned, int count) {
    if (count <= 0) return BigNumber.zero;
    final first = costOfNext(owned);
    if (growth == 1) return first * BigNumber.from(count);
    final g = BigNumber.from(growth);
    // first * (g^count - 1) / (g - 1)
    return first * (g.pow(count) - BigNumber.one) / (g - BigNumber.one);
  }

  @override
  int _estimate(int owned, BigNumber budget) {
    final first = costOfNext(owned);
    if (growth == 1) return (budget / first).floor().toDouble().floor();
    // Solve first * (g^n - 1)/(g - 1) = budget  =>  n = log_g(1 + budget*(g-1)/first)
    final g = BigNumber.from(growth);
    final inner = BigNumber.one + budget * (g - BigNumber.one) / first;
    return (inner.log10() / g.log10()).floor();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'geometric',
    'base': base.toJson(),
    'growth': growth,
  };
}

/// `base + step * owned`: the price rises by a fixed amount per unit.
class LinearCost extends CostCurve {
  LinearCost({required this.base, required this.step});

  final BigNumber base;
  final BigNumber step;

  @override
  BigNumber costOfNext(int owned) => base + step * BigNumber.from(owned);

  @override
  BigNumber totalCost(int owned, int count) {
    if (count <= 0) return BigNumber.zero;
    final c = BigNumber.from(count);
    // count * first + step * count*(count-1)/2
    return costOfNext(owned) * c +
        step * c * BigNumber.from(count - 1) / BigNumber.from(2);
  }

  @override
  int _estimate(int owned, BigNumber budget) {
    final first = costOfNext(owned);
    if (step.isZero) return (budget / first).toDouble().floor();
    // step/2 n^2 + (first - step/2) n - budget = 0
    final half = step / BigNumber.from(2);
    final b = first - half;
    final disc = b * b + BigNumber.from(4) * half * budget;
    final root = (-b + disc.sqrt()) / (BigNumber.from(2) * half);
    return root.toDouble().floor();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'linear',
    'base': base.toJson(),
    'step': step.toJson(),
  };
}
