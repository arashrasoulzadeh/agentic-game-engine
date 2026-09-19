import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import '../logic/projectile_helpers.dart';
import '../logic/weapon.dart';
import 'platformer_controller.dart';

/// Turns an entity's `InputState` (or a directly-set
/// `Weapon.attackRequested`, e.g. from AI or a touch button) plus its
/// `Weapon` into an actual attack — the input-reading half of combat,
/// mirroring `PlatformerInputSystem`'s "read an action, mutate/spawn
/// accordingly" shape.
///
/// Counts every `Weapon`'s `cooldownRemaining` down every tick
/// regardless of whether that entity has an `InputState` (so an
/// AI-controlled enemy's weapon still cools down normally), then fires
/// once per entity per tick where the attack action is held (or
/// `attackRequested` was already set) and [Weapon.isReady].
///
/// Both [WeaponKind]s reuse `spawnProjectile`/`installProjectileDamage`
/// (already registered by `installPlatformerSystems`/called by a game
/// via `installProjectileDamage`) rather than a separate hitbox
/// mechanism:
/// - [WeaponKind.ranged] spawns a projectile moving in the attacker's
///   facing direction (`PlatformerController.facingSign`, `1` if the
///   entity has no `PlatformerController`) at `Weapon.projectileSpeed`.
/// - [WeaponKind.melee] spawns a *stationary* projectile
///   (`vx: 0, vy: 0`) positioned `Weapon.meleeRange` ahead of the
///   attacker, alive for the short `Weapon.meleeDurationSeconds` — a
///   projectile that doesn't move and expires almost immediately reads
///   as an instantaneous swing hitbox, with zero new collision/damage
///   code needed.
///
/// A game must still call `installProjectileDamage(world)` once (the
/// same call ranged combat already needs) for either weapon kind to
/// actually deal damage on hit — this system only spawns the
/// hitbox/projectile, matching this package's "damage itself is an
/// explicit helper call, not automatic" convention (see
/// `installPlatformerSystems`'s doc comment).
class AttackSystem implements System {
  final String attackAction;

  /// When `true` (default `false`), the attack will only fire if there
  /// is a clear line of sight from the attacker to the attack's max
  /// range in the facing direction. Uses `WorldView.hasLineOfSight`
  /// against `TileMap` solid/one-way tiles. A wall between the attacker
  /// and the attack's max range will block the attack.
  ///
  /// The max range is:
  /// - [Weapon.meleeRange] for [WeaponKind.melee]
  /// - [Weapon.projectileSpeed] * [Weapon.projectileLifetimeSeconds] for [WeaponKind.ranged]
  ///
  /// Note: this does NOT check for entities in the way, only tile geometry.
  final bool requireLineOfSight;

  AttackSystem({this.attackAction = 'attack', this.requireLineOfSight = false});

  @override
  String get name => 'attack';

  @override
  void update(World world, double dt) {
    final weapons = world.storeOf<Weapon>();
    final positions = world.storeOf<Position>();
    final inputs = world.storeOf<InputState>();
    final controllers = world.storeOf<PlatformerController>();

    // Create WorldView once for line-of-sight checks
    final view = requireLineOfSight ? WorldView(world) : null;

    for (var i = 0; i < weapons.length; i++) {
      final entity = weapons.entityAt(i);
      final weapon = weapons.denseAt(i);

      if (weapon.cooldownRemaining > 0) weapon.cooldownRemaining -= dt;

      final input = inputs.get(entity);
      if (input != null && input.isPressed(attackAction)) {
        weapon.attackRequested = true;
      }

      if (weapon.attackRequested && weapon.isReady) {
        final pos = positions.get(entity);
        if (pos != null) {
          final facing = controllers.get(entity)?.facingSign ?? 1.0;

          // Check line of sight if required
          if (!requireLineOfSight || _hasLineOfSight(world, view!, pos, weapon, facing)) {
            _fire(world, entity, weapon, pos, facing);
            weapon.cooldownRemaining = weapon.cooldownSeconds;
          }
        }
        weapon.attackRequested = false;
      }
    }
  }

  /// Checks if there's a clear line of sight from [pos] to the attack's
  /// max range in the [facing] direction.
  bool _hasLineOfSight(World world, WorldView view, Position pos, Weapon weapon, double facing) {
    double maxRange;
    if (weapon.kind == WeaponKind.melee) {
      maxRange = weapon.meleeRange;
    } else {
      maxRange = weapon.projectileSpeed * weapon.projectileLifetimeSeconds;
    }

    final targetX = pos.x + maxRange * facing;
    final targetY = pos.y;

    return view.hasLineOfSight(pos.x, pos.y, targetX, targetY);
  }

  void _fire(World world, EntityId entity, Weapon weapon, Position pos, double facing) {
    switch (weapon.kind) {
      case WeaponKind.ranged:
        spawnProjectile(
          world,
          x: pos.x,
          y: pos.y,
          vx: weapon.projectileSpeed * facing,
          vy: 0,
          damage: weapon.damage,
          radius: weapon.projectileRadius,
          lifetimeSeconds: weapon.projectileLifetimeSeconds,
          owner: entity,
          atlasId: weapon.atlasId,
          spriteRegion: weapon.spriteRegion,
        );
      case WeaponKind.melee:
        spawnProjectile(
          world,
          x: pos.x + weapon.meleeRange * facing,
          y: pos.y,
          vx: 0,
          vy: 0,
          damage: weapon.damage,
          radius: weapon.meleeRadius,
          lifetimeSeconds: weapon.meleeDurationSeconds,
          owner: entity,
        );
    }
  }
}