import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'platformer_controller.dart';

/// Turns an entity's `InputState` into horizontal movement + jump
/// requests — the input-reading half of "moving"/"jumping" that every
/// platformer needs, so games don't hand-roll this System themselves
/// (this is exactly what `test_game`'s `_PlayerInputSystem` did before
/// this package existed). Attach the *same* `InputState` instance an
/// `InputController` owns to the player entity (see `spawnPlayer`) for
/// this to see live key presses.
///
/// Bindings default to `InputController.defaultBindings()`'s action
/// names (`"left"`/`"right"`/`"jump"`) — pass your own if you rebound
/// `InputController`.
///
/// Ignores all input entirely while `PlatformerController.hitstunSeconds
/// > 0` — a knockback impulse from `damageEntity` would otherwise be
/// overridden the very next tick by whatever direction the player still
/// happens to be holding.
///
/// Horizontal velocity snaps straight to the input target every tick
/// (`vel.x = vx`) unless `controller.groundFriction < 1.0` (see
/// `TileMap.frictionByTileId`), in which case it blends toward the
/// target instead — a lower value slides more (icy), the untagged-tile
/// default `1.0` is the original instant-snap behavior.
class PlatformerInputSystem implements System {
  final EntityId entity;
  final double moveSpeed;
  final String leftAction;
  final String rightAction;
  final String jumpAction;

  /// Action name for `DashSystem`'s dash — not in
  /// `InputController.defaultBindings()`, so bind it yourself the same
  /// way `test_game` binds `'pause'` to a key of your choice, or pass a
  /// different name here if you'd rather reuse an existing binding.
  final String dashAction;

  PlatformerInputSystem(
    this.entity, {
    this.moveSpeed = 160,
    this.leftAction = 'left',
    this.rightAction = 'right',
    this.jumpAction = 'jump',
    this.dashAction = 'dash',
  });

  @override
  String get name => 'platformerInput';

  @override
  void update(World world, double dt) {
    final input = world.storeOf<InputState>().get(entity);
    final vel = world.storeOf<Velocity>().get(entity);
    if (input == null || vel == null) return;

    final controller = world.storeOf<PlatformerController>().get(entity);
    if (controller != null && controller.hitstunSeconds > 0) return;

    var vx = 0.0;
    if (input.isPressed(leftAction)) vx -= moveSpeed;
    if (input.isPressed(rightAction)) vx += moveSpeed;
    if (controller != null && controller.grounded && controller.groundFriction < 1.0) {
      // Blend toward the target instead of snapping — groundFriction is
      // read from last tick's TileCollisionSystem pass (see
      // PlatformerController.groundFriction), so this is one tick stale
      // exactly like every other controller.grounded read here. A value
      // of 1.0 (the default, and every untagged tile) always takes the
      // snap branch below, so untouched behavior is unchanged.
      vel.x += (vx - vel.x) * controller.groundFriction;
    } else {
      vel.x = vx;
    }

    if (controller != null && vx != 0) {
      controller.facingSign = vx.sign;
    }

    if (input.isPressed(jumpAction)) {
      controller?.jumpRequested = true;
    }
    if (input.isPressed(dashAction)) {
      controller?.dashRequested = true;
    }
  }
}
