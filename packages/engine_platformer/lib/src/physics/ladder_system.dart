import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'platformer_controller.dart';

/// Turns vertical input into climbing movement while an entity overlaps
/// a `TileMap.ladderTileIds` tile (see `TileCollisionSystem`, which sets
/// `PlatformerController.onLadder`). A no-op for any controller with
/// `climbSpeed <= 0` (the default) — opting in is per-entity, same
/// "off by default" convention as every other feel field on
/// `PlatformerController`.
///
/// Only engages while up or down is actually held this tick — merely
/// overlapping a ladder tile (e.g. a jump arc that happens to pass
/// through or near one, or a coin placed inside the ladder's column)
/// must never by itself override `Velocity.y`. An earlier version
/// unconditionally zeroed `vel.y` and cleared `grounded` on any overlap
/// regardless of input, which silently killed the vertical velocity of
/// any jump that so much as grazed a ladder tile — found live in
/// `test_game`, where a coin sitting inside the ladder's own tile
/// column made jumping toward it look like a "falling" bug (the jump's
/// upward velocity got zeroed by this system the instant the collider
/// touched the ladder, well before the player pressed up/down to
/// actually grab it).
///
/// Runs after `JumpSystem` in `installPlatformerSystems` so it has the
/// final say on `Velocity.y` this tick: while climbing (up/down held on
/// a ladder), gravity and any jump impulse from earlier this tick are
/// overridden with a direct climb velocity. A jump fires normally by
/// simply not holding up/down — this system does nothing that tick,
/// leaving `JumpSystem`'s own `vel.y` write (and gravity/tile collision
/// around it) completely untouched.
class LadderSystem implements System {
  final EntityId entity;
  final String upAction;
  final String downAction;

  LadderSystem(this.entity, {this.upAction = 'up', this.downAction = 'down'});

  @override
  String get name => 'ladder';

  @override
  void update(World world, double dt) {
    final controller = world.storeOf<PlatformerController>().get(entity);
    if (controller == null || controller.climbSpeed <= 0) return;
    if (!controller.onLadder) return;
    if (controller.hitstunSeconds > 0) return;

    final input = world.storeOf<InputState>().get(entity);
    final vel = world.storeOf<Velocity>().get(entity);
    if (input == null || vel == null) return;

    final wantsUp = input.isPressed(upAction);
    final wantsDown = input.isPressed(downAction);
    if (!wantsUp && !wantsDown) return;

    var vy = 0.0;
    if (wantsUp) vy -= controller.climbSpeed;
    if (wantsDown) vy += controller.climbSpeed;

    vel.y = vy;
    controller.grounded = false;
  }
}
