/// Authored knobs for randomised waves (`"random_waves"` in the level JSON).
class RandomWaves {
  const RandomWaves({
    this.eliteChance = 0.2,
    this.eliteHp = 2.2,
    this.eliteAttack = 1.4,
    this.eliteScale = 1.18,
    this.eliteCoins = 3,
    this.treasureChance = 0.35,
    this.treasureEnemy,
    this.treasureHp = 1.6,
    this.treasureAttack = 0.15,
    this.treasureCoins = 8,
    this.shuffleBlock = 4,
  });

  /// Chance each wave after the first is an elite.
  final double eliteChance;

  /// Elite multipliers on hp and attack, drawn size, and coin reward.
  final double eliteHp;
  final double eliteAttack;
  final double eliteScale;
  final int eliteCoins;

  /// Chance a run contains one treasure enemy, and which enemy art it uses
  /// (null = no treasure). It is harmless but tanky and pays [treasureCoins].
  final double treasureChance;
  final String? treasureEnemy;
  final double treasureHp;
  final double treasureAttack;
  final int treasureCoins;

  /// Waves are shuffled inside blocks of this many.
  final int shuffleBlock;

  factory RandomWaves.fromJson(Map<String, dynamic> j) => RandomWaves(
    eliteChance: (j['elite_chance'] as num?)?.toDouble() ?? 0.2,
    eliteHp: (j['elite_hp'] as num?)?.toDouble() ?? 2.2,
    eliteAttack: (j['elite_attack'] as num?)?.toDouble() ?? 1.4,
    eliteScale: (j['elite_scale'] as num?)?.toDouble() ?? 1.18,
    eliteCoins: (j['elite_coins'] as num?)?.toInt() ?? 3,
    treasureChance: (j['treasure_chance'] as num?)?.toDouble() ?? 0.35,
    treasureEnemy: j['treasure_enemy'] as String?,
    treasureHp: (j['treasure_hp'] as num?)?.toDouble() ?? 1.6,
    treasureAttack: (j['treasure_attack'] as num?)?.toDouble() ?? 0.15,
    treasureCoins: (j['treasure_coins'] as num?)?.toInt() ?? 8,
    shuffleBlock: (j['shuffle_block'] as num?)?.toInt() ?? 4,
  );
}
