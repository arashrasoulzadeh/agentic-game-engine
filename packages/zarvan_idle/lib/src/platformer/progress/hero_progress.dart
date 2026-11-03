import 'dart:math' as math;

/// One purchasable hero improvement in a wave-combat game.
class HeroUpgrade {
  const HeroUpgrade({
    required this.id,
    required this.label,
    required this.stat,
    this.perLevel = 0.25,
    this.baseCost = 20,
    this.costGrowth = 1.6,
    this.maxLevel = 20,
  });

  /// Stable key progress is stored under.
  final String id;

  /// Button text.
  final String label;

  /// Which fighter stat it raises: `hp`, `attack`, `armor` or `attack_speed`.
  final String stat;

  /// Each level adds this fraction of the base stat (0.25 = +25% of base).
  final double perLevel;

  /// Coins for the first level; each further level costs [costGrowth] times
  /// the previous one.
  final double baseCost;
  final double costGrowth;
  final int maxLevel;
}

/// The hero's coins and upgrade levels, kept by the game (not the scene) so
/// they survive a retry: a new run starts from wave 1 with everything bought.
class HeroProgress {
  HeroProgress({this.coins = 0, Map<String, int>? levels})
    : _levels = {...?levels};

  int coins;
  final Map<String, int> _levels;

  int levelOf(HeroUpgrade upgrade) => _levels[upgrade.id] ?? 0;

  bool isMaxed(HeroUpgrade upgrade) => levelOf(upgrade) >= upgrade.maxLevel;

  /// Coins the next level costs, rounded up to a whole coin.
  int costOf(HeroUpgrade upgrade) =>
      (upgrade.baseCost * math.pow(upgrade.costGrowth, levelOf(upgrade)))
          .ceil();

  bool canBuy(HeroUpgrade upgrade) =>
      !isMaxed(upgrade) && coins >= costOf(upgrade);

  /// Buys one level; false (and nothing changes) when it cannot be afforded
  /// or is already at its maximum.
  bool buy(HeroUpgrade upgrade) {
    if (!canBuy(upgrade)) return false;
    coins -= costOf(upgrade);
    _levels[upgrade.id] = levelOf(upgrade) + 1;
    return true;
  }

  /// The factor applied to the base [stat]: 1 plus every bought level's
  /// `perLevel` of the upgrades in [upgrades] that raise it.
  double multiplier(String stat, Iterable<HeroUpgrade> upgrades) {
    var m = 1.0;
    for (final u in upgrades) {
      if (u.stat == stat) m += u.perLevel * levelOf(u);
    }
    return m;
  }
}
