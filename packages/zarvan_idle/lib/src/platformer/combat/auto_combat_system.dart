import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_platformer/zarvan_platformer.dart';

import 'combat_components.dart';
import 'enemy_powers.dart';
import 'conditions.dart';

/// Auto-attacks; on damage calls engine [flashHit] for red tint feedback.
class AutoCombatSystem extends System {
  /// While false fighters stand down — e.g. the hero is still walking to the
  /// next enemy.
  bool enabled = true;

  /// Seconds before a fighter's attack at which an [AttackWindup] event is
  /// emitted so the hit can be telegraphed (0 = never).
  double windupSeconds = 0;

  /// Extra multipliers on a side's damage (a combo for the hero, a guard on
  /// the enemy's hits...). Each gets the attacker's side; the factor applied is
  /// their product.
  final List<double Function(String side)> damageModifiers = [];

  /// The combined damage factor for attacks by [side].
  double damageFactor(String side) {
    var f = 1.0;
    for (final m in damageModifiers) {
      f *= m(side);
    }
    if (side == 'hero' && _counterLeft > 0) f *= counterBonus;
    return f;
  }

  /// Turns on [tap]: parrying a telegraphed attack and timing a strike. Off by
  /// default, so a game that never calls [tap] fights exactly as before.
  bool playerTiming = false;

  /// A tap this close before the hero's own attack makes it a timed strike
  /// (always critical).
  double strikeWindowSeconds = 0.25;

  /// A tap outside every window locks [tap] for this long, so mashing the
  /// screen cannot cover every window.
  double missLockoutSeconds = 0.5;

  /// After a parry the hero's damage is multiplied by [counterBonus] for
  /// [counterSeconds].
  double counterBonus = 1.5;
  double counterSeconds = 2;

  /// Damage multiplier of a timed strike (at least the hero's own crit
  /// multiplier).
  double timedStrikeMultiplier = 2;

  /// How much of the [ultimate] meter (0..1) each of these fills.
  double ultimateGainPerHit = 0.04;
  double ultimateGainPerParry = 0.34;
  double ultimateGainPerTimedStrike = 0.2;

  /// The hero's ultimate meter, 0..1. A skill flagged `ultimate` needs it full.
  double ultimate = 0;

  /// Which enemy the hero attacks. Falls back to the first living enemy when
  /// null, dead or not an enemy, so a single-enemy fight needs no setup.
  EntityId? focus;

  double _lockout = 0;
  double _counterLeft = 0;
  bool _strikeArmed = false;
  final Set<EntityId> _parried = {};

  /// Seconds left before [tap] works again after a mistimed tap.
  double get lockoutLeft => _lockout;

  /// Seconds left of the counter-attack bonus.
  double get counterLeft => _counterLeft;

  final Set<EntityId> _winding = {};

  @override
  String get name => 'autoCombat';

  /// The living hero and the living enemies, in spawn order.
  (EntityId?, List<EntityId>) _fighters(World world) {
    final roles = world.componentsOf<CombatRole>();
    final health = world.componentsOf<Health>();
    EntityId? hero;
    final enemies = <EntityId>[];
    for (var i = 0; i < roles.length; i++) {
      final e = roles.entityAt(i);
      if (!health.has(e) || health.get(e)!.current <= 0) continue;
      final side = roles.denseAt(i).side;
      if (side == 'hero') hero = e;
      if (side == 'enemy') enemies.add(e);
    }
    return (hero, enemies);
  }

  /// The enemy the hero attacks now: [focus] if it is alive, else the first.
  EntityId? targetOf(List<EntityId> enemies) =>
      focus != null && enemies.contains(focus) ? focus : enemies.firstOrNull;

  @override
  void update(World world, double dt) {
    if (!enabled) return;
    _lockout = math.max(0, _lockout - dt);
    _counterLeft = math.max(0, _counterLeft - dt);
    final (hero, enemies) = _fighters(world);
    if (hero == null || enemies.isEmpty) return;

    _tick(world, dt, hero, targetOf(enemies)!);
    for (final enemy in enemies) {
      _tick(world, dt, enemy, hero);
    }
  }

  /// The player's tap on the battlefield. With [playerTiming] on: a tap while an
  /// enemy is winding up its attack parries it (the hit is cancelled, the
  /// counter bonus starts, the ultimate fills); a tap just before the hero's
  /// own attack makes that attack a timed strike; any other tap is a miss that
  /// locks [tap] for [missLockoutSeconds].
  TapResult tap(World world) {
    if (!playerTiming || !enabled) return TapResult.none;
    if (_lockout > 0) return TapResult.locked;
    final (hero, enemies) = _fighters(world);
    if (hero == null || enemies.isEmpty) return TapResult.none;
    final stats = world.componentsOf<CombatStats>();

    EntityId? soonest;
    for (final e in enemies) {
      if (!_winding.contains(e) || _parried.contains(e)) continue;
      if (soonest == null ||
          stats.get(e)!.cooldown < stats.get(soonest)!.cooldown) {
        soonest = e;
      }
    }
    if (soonest != null) {
      _parried.add(soonest);
      _counterLeft = counterSeconds;
      _gain(ultimateGainPerParry);
      world.events.emit(AttackParried(attacker: soonest, defender: hero));
      return TapResult.parried;
    }
    final heroCooldown = stats.get(hero)!.cooldown;
    if (!_strikeArmed &&
        heroCooldown > 0 &&
        heroCooldown <= strikeWindowSeconds) {
      _strikeArmed = true;
      return TapResult.timedStrike;
    }
    _lockout = missLockoutSeconds;
    world.events.emit(TapMissed());
    return TapResult.missed;
  }

  void _gain(double amount) => ultimate = (ultimate + amount).clamp(0.0, 1.0);

  /// Empties the ultimate meter if it is full; true when it was.
  bool spendUltimate() {
    if (ultimate < 1) return false;
    ultimate = 0;
    return true;
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

    if (world.componentsOf<Conditions>().get(attacker)?.stunned ?? false) {
      return;
    }
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
    if (_parried.remove(attacker)) return; // parried: the swing hits nothing
    final timed = side == 'hero' && _strikeArmed;
    if (timed) {
      _strikeArmed = false;
      world.events.emit(TimedStrike(attacker: attacker));
      _gain(ultimateGainPerTimedStrike);
    }

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
    attack *= damageFactor(side);
    final armor = stats.get(defender)!.armor;
    final hp = health.get(defender)!;

    // Every Nth attack of an archer is a volley: several lighter arrows.
    mine?.attacksMade++;
    final volley =
        mine != null &&
        mine.volleyEvery > 0 &&
        mine.attacksMade % mine.volleyEvery == 0;
    final blows = volley ? mine.volleyArrows : 1;
    for (var i = 0; i < blows; i++) {
      if (hp.current <= 0) break;
      final raw = (volley ? attack * mine.volleyDamage : attack) - armor;
      final base = raw < 1 ? 1.0 : raw;
      final critical =
          timed ||
          (s.critChance > 0 && world.random.nextDouble() < s.critChance);
      final mult = timed
          ? math.max(s.critMultiplier, timedStrikeMultiplier)
          : s.critMultiplier;
      final dmg = critical ? base * mult : base;
      if (side == 'hero') _gain(ultimateGainPerHit);
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
    if (mine != null && hp.current > 0) _applyConditions(world, mine, defender);
  }

  /// Puts the attacker's bleed, poison and stun on the defender.
  void _applyConditions(World world, EnemyPowers p, EntityId defender) {
    if (p.bleedFraction <= 0 && p.poisonFraction <= 0 && p.stunChance <= 0) {
      return;
    }
    final store = world.componentsOf<Conditions>();
    var fx = store.get(defender);
    if (fx == null) {
      fx = Conditions();
      store.set(defender, fx);
    }
    if (p.bleedFraction > 0) {
      fx.apply(
        ConditionKind.bleed,
        seconds: p.bleedSeconds,
        dpsFraction: p.bleedFraction,
      );
    }
    if (p.poisonFraction > 0) {
      fx.apply(
        ConditionKind.poison,
        seconds: p.poisonSeconds,
        dpsFraction: p.poisonFraction,
        maxStacks: p.poisonMaxStacks,
      );
    }
    if (p.stunChance > 0 && world.random.nextDouble() < p.stunChance) {
      fx.apply(ConditionKind.stun, seconds: p.stunSeconds);
    }
  }
}
