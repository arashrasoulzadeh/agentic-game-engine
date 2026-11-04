import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' show Text;

import '../hud/world_text.dart';
import 'auto_combat_system.dart';
import 'combat_components.dart';

/// A damage combo: each consecutive hit by the hero adds [bonusPerHit] of its
/// damage (up to [maxHits] hits) and a hit the hero takes resets it. Shows a
/// "Combo xN" label from the second hit.
class ComboTracker {
  ComboTracker.install(
    World world,
    AutoCombatSystem combat, {
    required this.bonusPerHit,
    required this.maxHits,
    double labelX = 145,
    double labelY = 64,
  }) {
    _label = spawnWorldText(
      world,
      labelX,
      labelY,
      '',
      fontSize: 5.4,
      colorArgb: 0xFFFFC93C,
      zIndex: 125,
    );
    combat.damageModifiers.add((side) => side == 'hero' ? multiplier : 1);
    world.events.on<FighterHit>((hit) {
      count = hit.attackerSide == 'hero' ? count + 1 : 0;
      _sync(world);
    });
  }

  final double bonusPerHit;
  final int maxHits;

  /// Consecutive hero hits so far.
  int count = 0;
  late final EntityId _label;

  /// The hero's damage multiplier right now.
  double get multiplier => 1 + math.min(count, maxHits) * bonusPerHit;

  void _sync(World world) {
    world.componentsOf<Text>().get(_label)?.text = count >= 2
        ? 'Combo x$count'
        : '';
  }
}
