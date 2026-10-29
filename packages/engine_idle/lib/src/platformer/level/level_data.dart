import 'parallax.dart';

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
    this.parallax = const [],
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

  /// Scrolling background layers, far to near; empty = none.
  final List<ParallaxSpec> parallax;

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
    parallax: [
      for (final l in (json['parallax'] as List?) ?? const [])
        ParallaxSpec.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );

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
