import 'big_number.dart';

/// A team's or player's stock of named resources, as [BigNumber]s: the idle-game counterpart of
/// `Treasury`, which counts whole units in 64-bit ints and so cannot hold an incremental game's
/// totals.
///
/// Amounts are continuous (no separate fractional carry is needed: a [BigNumber] holds 0.3 of a
/// coin), so show players a floored or formatted value, and test affordability with [canAfford].
/// Income per second accrues by [accrue]; it is correct for any `dt`, including the hours-long steps
/// offline catch-up uses.
class BigTreasury {
  /// Resource name -> amount held.
  final Map<String, BigNumber> amounts;

  /// Resource name -> amount gained per second while [accrue] runs.
  final Map<String, BigNumber> incomePerSecond;

  BigTreasury({
    Map<String, BigNumber>? amounts,
    Map<String, BigNumber>? incomePerSecond,
  }) : amounts = amounts ?? {},
       incomePerSecond = incomePerSecond ?? {};

  /// How much of [resource] is held (zero if never touched).
  BigNumber of(String resource) => amounts[resource] ?? BigNumber.zero;

  /// The income rate of [resource] (zero if none).
  BigNumber rateOf(String resource) =>
      incomePerSecond[resource] ?? BigNumber.zero;

  /// Whether every entry of [cost] is covered.
  bool canAfford(Map<String, BigNumber> cost) =>
      cost.entries.every((e) => of(e.key) >= e.value);

  /// Takes all of [cost] or nothing: false (and no change) if any entry is short.
  bool spend(Map<String, BigNumber> cost) {
    if (!canAfford(cost)) return false;
    for (final e in cost.entries) {
      amounts[e.key] = of(e.key) - e.value;
    }
    return true;
  }

  /// Adds [amount] of [resource].
  void add(String resource, BigNumber amount) =>
      amounts[resource] = of(resource) + amount;

  /// Advances every income by [dt] seconds. Any `dt` works: one step of 6 hours gives the same result
  /// as 21,600 steps of one second, because income is rate times time.
  void accrue(double dt) {
    if (dt <= 0) return;
    final seconds = BigNumber.from(dt);
    for (final e in incomePerSecond.entries) {
      add(e.key, e.value * seconds);
    }
  }

  Map<String, dynamic> toJson() => {
    'amounts': {for (final e in amounts.entries) e.key: e.value.toJson()},
    'incomePerSecond': {
      for (final e in incomePerSecond.entries) e.key: e.value.toJson(),
    },
  };

  factory BigTreasury.fromJson(Map<String, dynamic> json) {
    Map<String, BigNumber> read(String key) => {
      for (final e in ((json[key] as Map?) ?? const {}).entries)
        e.key as String: BigNumber.fromJson(e.value as Object),
    };
    return BigTreasury(
      amounts: read('amounts'),
      incomePerSecond: read('incomePerSecond'),
    );
  }
}
