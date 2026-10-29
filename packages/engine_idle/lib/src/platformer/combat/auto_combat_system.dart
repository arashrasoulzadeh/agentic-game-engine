import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';

import 'combat_components.dart';

/// Auto-attacks; on damage calls engine [flashHit] for red tint feedback.
class AutoCombatSystem extends System {
  @override
  String get name => 'autoCombat';

  @override
  void update(World world, double dt) {
    final roles = world.storeOf<CombatRole>();
    final health = world.storeOf<Health>();

    EntityId? hero;
    EntityId? enemy;
    for (var i = 0; i < roles.length; i++) {
      final e = roles.entityAt(i);
      if (!health.has(e) || health.get(e)!.current <= 0) continue;
      final side = roles.denseAt(i).side;
      if (side == 'hero') hero = e;
      if (side == 'enemy') enemy = e;
    }
    if (hero == null || enemy == null) return;

    _tick(world, dt, hero, enemy);
    _tick(world, dt, enemy, hero);
  }

  void _tick(World world, double dt, EntityId attacker, EntityId defender) {
    final stats = world.storeOf<CombatStats>();
    final s = stats.get(attacker)!;
    s.cooldown -= dt;
    if (s.cooldown > 0) return;
    s.cooldown = 1.0 / s.attackSpeed.clamp(0.05, 10);
    final raw = s.attack - stats.get(defender)!.armor;
    final hp = world.storeOf<Health>().get(defender)!;
    hp.current = (hp.current - (raw < 1 ? 1.0 : raw)).clamp(0, hp.max);
    flashHit(world, defender);
  }
}
