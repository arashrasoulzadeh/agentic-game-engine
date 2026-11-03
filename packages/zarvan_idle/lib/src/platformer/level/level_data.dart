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
    enemyRampStart:
        ((json['enemy_ramp'] as Map?)?['start'] as num?)?.toDouble() ?? 1,
    enemyRampWaves: ((json['enemy_ramp'] as Map?)?['waves'] as num?)?.toInt() ?? 0,
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
  List<String> get enemyIds => [...wave, boss];

  /// [base] times this level's preview multiplier for [stat] (1 if unset).
  double scaled(String stat, double base) => base * (previewScale[stat] ?? 1);

  /// [base] times the boss multiplier for [stat] (1 if unset).
  double bossScaled(String stat, double base) =>
      base * (previewBossScale[stat] ?? 1);
}
