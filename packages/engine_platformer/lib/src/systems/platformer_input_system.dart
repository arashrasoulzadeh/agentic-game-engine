import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import '../components/platformer_controller.dart';

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
class PlatformerInputSystem implements System {
  final EntityId entity;
  final double moveSpeed;
  final String leftAction;
  final String rightAction;
  final String jumpAction;

  PlatformerInputSystem(
    this.entity, {
    this.moveSpeed = 160,
    this.leftAction = 'left',
    this.rightAction = 'right',
    this.jumpAction = 'jump',
  });

  @override
  String get name => 'platformerInput';

  @override
  void update(World world, double dt) {
    final input = world.storeOf<InputState>().get(entity);
    final vel = world.storeOf<Velocity>().get(entity);
    if (input == null || vel == null) return;

    var vx = 0.0;
    if (input.isPressed(leftAction)) vx -= moveSpeed;
    if (input.isPressed(rightAction)) vx += moveSpeed;
    vel.x = vx;

    if (input.isPressed(jumpAction)) {
      final controller = world.storeOf<PlatformerController>().get(entity);
      controller?.jumpRequested = true;
    }
  }
}
