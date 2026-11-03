import 'package:zarvan_flutter/zarvan_flutter.dart'
    show AnimationEvent, ParallaxSpec;

/// Animation cues per state and frame: `{'attack': {2: [AnimationEvent(...)]}}`.
/// Handed to the engine's cue systems (shake, particles, sfx) when that frame
/// of that state plays.
typedef StateCues = Map<String, Map<int, List<AnimationEvent>>>;

/// Top-left pixel anchor for a fighter's sprite cell.
class Anchor {
  const Anchor(this.x, this.y);

  final double x;
  final double y;

  factory Anchor.fromJson(Map<String, dynamic> json) =>
      Anchor((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

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

/// Typed view of a level JSON (`assets/levels/*.json`), so scenes never
/// poke at raw maps.
class LevelData {
  const LevelData({
    required this.name,
    required this.gdd,
    required this.wave,
    required this.boss,
    required this.background,
    required this.hero,
    required this.enemyAnchor,
    this.previewScale = const {},
    this.previewBossScale = const {},
    this.randomWaves,
    this.enemyRampStart = 1,
    this.enemyRampWaves = 0,
    this.heroCritChance = 0,
    this.heroCritMultiplier = 1.5,
    this.parallax = const [],
    this.cues = const {},
  });

  final String name;
  final String gdd;
  final List<String> wave;
  final String boss;
  final String background;
  final Anchor hero;
  final Anchor enemyAnchor;

  /// Per-stat multipliers applied to the hero for preview balancing.
  final Map<String, double> previewScale;

  /// Per-stat multipliers on the boss. Roster boss stats assume a levelled
  /// hero, so a preview with an unlevelled one tones the boss down here.
  final Map<String, double> previewBossScale;

  /// Randomised enemy order with elites and a treasure enemy; null = the
  /// wave list is played as written.
  final RandomWaves? randomWaves;

  /// Early-game ease: normal enemies (not the boss) start at this fraction of
  /// their hp and attack and reach full strength after [enemyRampWaves] waves.
  /// 1 (default) means no ramp.
  final double enemyRampStart;
  final int enemyRampWaves;

  /// The hero's critical-hit chance (0..1) and damage multiplier.
  final double heroCritChance;
  final double heroCritMultiplier;

  /// Multiplier for the normal enemy of wave [index] (0-based).
  double enemyRamp(int index) {
    if (enemyRampWaves <= 0 || enemyRampStart >= 1) return 1;
    final t = (index / enemyRampWaves).clamp(0.0, 1.0);
    return enemyRampStart + (1 - enemyRampStart) * t;
  }

  /// Scrolling background layers, far to near; empty = none.
  final List<ParallaxSpec> parallax;

  /// Cue events fired on given frames of fighter states, e.g. a camera shake
  /// on the frame an attack lands. Authored as data in the level JSON:
  /// `"cues": {"attack": {"2": [{"type": "shake", "data": {...}}]}}`.
  final StateCues cues;

  factory LevelData.fromJson(Map<String, dynamic> json) => LevelData(
    name: json['name'] as String? ?? '',
    gdd: json['gdd'] as String? ?? '',
    wave: (json['wave'] as List).cast<String>(),
    boss: json['boss'] as String,
    background: json['background'] as String,
    hero: Anchor.fromJson((json['hero'] as Map).cast<String, dynamic>()),
    enemyAnchor: Anchor.fromJson(
      (json['enemy_anchor'] as Map).cast<String, dynamic>(),
    ),
    previewScale: _scales(json['preview_hero_scale']),
    previewBossScale: _scales(json['preview_boss_scale']),
    randomWaves: json['random_waves'] is Map
        ? RandomWaves.fromJson(
            (json['random_waves'] as Map).cast<String, dynamic>(),
          )
        : null,
    enemyRampStart:
        ((json['enemy_ramp'] as Map?)?['start'] as num?)?.toDouble() ?? 1,
    enemyRampWaves:
        ((json['enemy_ramp'] as Map?)?['waves'] as num?)?.toInt() ?? 0,
    heroCritChance:
        ((json['hero_crit'] as Map?)?['chance'] as num?)?.toDouble() ?? 0,
    heroCritMultiplier:
        ((json['hero_crit'] as Map?)?['multiplier'] as num?)?.toDouble() ?? 1.5,
    cues: _cues(json['cues']),
    parallax: [
      for (final l in (json['parallax'] as List?) ?? const [])
        ParallaxSpec.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );

  static StateCues _cues(Object? raw) => {
    for (final state in ((raw as Map?) ?? const {}).entries)
      state.key as String: {
        for (final frame in (state.value as Map).entries)
          int.parse(frame.key as String): [
            for (final e in frame.value as List)
              AnimationEvent.fromJson(Map<String, dynamic>.from(e as Map)),
          ],
      },
  };

  static Map<String, double> _scales(Object? raw) => {
    for (final e in ((raw as Map?) ?? const {}).entries)
      e.key as String: (e.value as num).toDouble(),
  };

  /// Every enemy id whose sheet must be loaded (wave + boss).
  List<String> get enemyIds => [
    ...wave,
    boss,
    if (randomWaves?.treasureEnemy != null &&
        !wave.contains(randomWaves!.treasureEnemy))
      randomWaves!.treasureEnemy!,
  ];

  /// [base] times this level's preview multiplier for [stat] (1 if unset).
  double scaled(String stat, double base) => base * (previewScale[stat] ?? 1);

  /// [base] times the boss multiplier for [stat] (1 if unset).
  double bossScaled(String stat, double base) =>
      base * (previewBossScale[stat] ?? 1);
}
