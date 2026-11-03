import 'dart:math' as math;

import 'level_data.dart';

/// What kind of enemy a wave slot holds.
enum WaveKind {
  /// The wave's own enemy.
  normal,

  /// A tougher, larger version: more health and attack, more coins.
  elite,

  /// A rare, nearly harmless enemy worth many coins.
  treasure,
}

/// The enemy order of one run: the level's waves, shuffled in small blocks,
/// with some turned into elites and, rarely, a treasure enemy. Built fresh for
/// each run so runs differ; pass a seeded [math.Random] to repeat one.
class WavePlan {
  WavePlan(this.ids, this.kinds)
    : assert(ids.length == kinds.length, 'one kind per wave');

  /// Enemy id per wave slot.
  final List<String> ids;
  final List<WaveKind> kinds;

  /// The level's order, untouched, all normal (random waves off).
  factory WavePlan.fixed(LevelData level) => WavePlan(
    List.of(level.wave),
    List.filled(level.wave.length, WaveKind.normal),
  );

  factory WavePlan.generate(LevelData level, math.Random random) {
    final cfg = level.randomWaves;
    if (cfg == null) return WavePlan.fixed(level);
    final ids = List.of(level.wave);
    // Shuffle inside blocks so the difficulty curve is kept.
    final block = math.max(1, cfg.shuffleBlock);
    for (var start = 0; start < ids.length; start += block) {
      final end = math.min(start + block, ids.length);
      final part = ids.sublist(start, end)..shuffle(random);
      ids.setRange(start, end, part);
    }
    final kinds = List.filled(ids.length, WaveKind.normal);
    // The first wave stays plain so a run opens gently.
    for (var i = 1; i < ids.length; i++) {
      if (random.nextDouble() < cfg.eliteChance) kinds[i] = WaveKind.elite;
    }
    final treasure = cfg.treasureEnemy;
    if (treasure != null && ids.length > 2) {
      final slot = 1 + random.nextInt(ids.length - 1);
      if (random.nextDouble() < cfg.treasureChance) {
        ids[slot] = treasure;
        kinds[slot] = WaveKind.treasure;
      }
    }
    return WavePlan(ids, kinds);
  }
}
