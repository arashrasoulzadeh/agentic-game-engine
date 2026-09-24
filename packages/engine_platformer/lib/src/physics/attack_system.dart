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
/// For melee weapons with [Weapon.comboCount] > 1, a successful hit
/// starts a [Weapon.comboWindowSeconds] timer. If the attack action is
/// pressed again before the timer expires, the next combo step fires
/// immediately (bypassing normal cooldown). Missing the window or a whiff
/// (hitbox not connecting) resets the combo to step 0.
///
/// A game must still call `installProjectileDamage(world)` once (the
/// same call ranged combat already needs) for either weapon kind to
/// actually deal damage on hit — this system only spawns the
/// hitbox/projectile, matching this package's "damage itself is an
/// explicit helper call, not automatic" convention (see
/// `installPlatformerSystems`'s doc comment).
class AttackSystem implements System {
  final String attackAction;
  final bool requireLineOfSight;

  bool _listenersRegistered = false;

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

    // Register melee hit listener once (for combo windows)
    if (!_listenersRegistered) {
      world.events.on<MeleeHitEvent>((event) {
        final weapon = weapons.get(event.attacker);
        if (weapon != null && weapon.kind == WeaponKind.melee && weapon.comboCount > 1) {
          // Start combo window for next hit
          weapon.comboTimer = weapon.comboWindowSeconds;
          weapon.advanceCombo();
        }
      });
      _listenersRegistered = true;
    }

    for (var i = 0; i < weapons.length; i++) {
      final entity = weapons.entityAt(i);
      final weapon = weapons.denseAt(i);

      // Count down cooldown
      if (weapon.cooldownRemaining > 0) weapon.cooldownRemaining -= dt;

      // Count down combo window
      if (weapon.comboTimer > 0) {
        weapon.comboTimer -= dt;
        if (weapon.comboTimer <= 0) {
          // Combo window expired - reset combo
          weapon.resetCombo();
        }
      }

      final input = inputs.get(entity);
      if (input != null && input.isPressed(attackAction)) {
        weapon.attackRequested = true;
      }

      // Check if we can fire: either normal ready, or in combo window with attack buffered
      final requested = weapon.attackRequested;
      final canFireNormal = requested && weapon.isReady;
      final canFireCombo = requested &&
          weapon.comboTimer > 0 &&
          weapon.currentComboStep > 0 &&
          weapon.currentComboStep < weapon.comboCount;

      // Always consume attack request each tick (matches original behavior)
      weapon.attackRequested = false;

      if (canFireNormal || canFireCombo) {
        final pos = positions.get(entity);
        if (pos != null) {
          final facing = controllers.get(entity)?.facingSign ?? 1.0;

          // Check line of sight if required
          if (!requireLineOfSight || _hasLineOfSight(world, view!, pos, weapon, facing)) {
            _fire(world, entity, weapon, pos, facing);
            weapon.cooldownRemaining = weapon.currentCooldown;
          }
        }
      }
    }
  }

  /// Checks if there's a clear line of sight from [pos] to the attack's
  /// max range in the [facing] direction.
  bool _hasLineOfSight(World world, WorldView view, Position pos, Weapon weapon, double facing) {
    double maxRange;
    if (weapon.kind == WeaponKind.melee) {
      maxRange = weapon.currentMeleeRange;
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
          x: pos.x + weapon.currentMeleeRange * facing,
          y: pos.y,
          vx: 0,
          vy: 0,
          damage: weapon.currentDamage,
          radius: weapon.currentMeleeRadius,
          lifetimeSeconds: weapon.currentMeleeDuration,
          owner: entity,
        );
    }
  }
}