import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_platformer/zarvan_platformer.dart';

import 'combat_components.dart';
import 'enemy_powers.dart';

/// Auto-attacks; on damage calls engine [flashHit] for red tint feedback.
class AutoCombatSystem extends System {
  /// While false fighters stand down — e.g. the hero is still walking to the
  /// next enemy.
  bool enabled = true;

  /// Seconds before a fighter's attack at which an [AttackWindup] event is
  /// emitted so the hit can be telegraphed (0 = never).
  double windupSeconds = 0;

  /// Extra multiplier on a side's damage (e.g. a combo bonus for `hero`).
  double Function(String side)? damageMultiplier;

  final Set<EntityId> _winding = {};

  @override
  String get name => 'autoCombat';

  @override
  void update(World world, double dt) {
    if (!enabled) return;
    final roles = world.componentsOf<CombatRole>();
    final health = world.componentsOf<Health>();

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
    final stats = world.componentsOf<CombatStats>();
    final health = world.componentsOf<Health>();
    final powers = world.componentsOf<EnemyPowers>();
    final s = stats.get(attacker)!;
    final mine = powers.get(attacker);
    final hpNow = health.get(attacker)!;
    final raging =
        mine != null && mine.rageActive(hpNow.current / math.max(1, hpNow.max));
    final speed = s.attackSpeed * (raging ? mine.rageAttackSpeed : 1);
    final side = world.componentsOf<CombatRole>().get(attacker)!.side;

    s.cooldown -= dt;
    if (windupSeconds > 0 &&
        s.cooldown > 0 &&
        s.cooldown <= windupSeconds &&
        _winding.add(attacker)) {
      world.events.emit(
        AttackWindup(
          attacker: attacker,
          attackerSide: side,
          seconds: s.cooldown,
        ),
      );
    }
    if (s.cooldown > 0) return;
    _winding.remove(attacker);
    s.cooldown = 1.0 / speed.clamp(0.05, 10);
    playSpriteState(world, attacker, 'attack');

    final theirs = powers.get(defender);
    if (theirs != null &&
        theirs.dodge > 0 &&
        world.random.nextDouble() < theirs.dodge) {
      world.events.emit(FighterDodge(attacker: attacker, defender: defender));
      return;
    }

    var attack = s.attack * (raging ? mine.rageAttack : 1);
    if (mine != null && mine.firstStrike != 1 && !mine.firstStrikeUsed) {
      mine.firstStrikeUsed = true;
      attack *= mine.firstStrike;
    }
    attack *= damageMultiplier?.call(side) ?? 1;
    final raw = attack - stats.get(defender)!.armor;
    final hp = health.get(defender)!;
    final base = raw < 1 ? 1.0 : raw;
    final critical =
        s.critChance > 0 && world.random.nextDouble() < s.critChance;
    final dmg = critical ? base * s.critMultiplier : base;
    hp.current = (hp.current - dmg).clamp(0, hp.max);
    flashHit(world, defender);
    world.events.emit(
      FighterHit(
        attacker: attacker,
        defender: defender,
        attackerSide: side,
        damage: dmg,
        fatal: hp.current <= 0,
        critical: critical,
      ),
    );
  }
}
