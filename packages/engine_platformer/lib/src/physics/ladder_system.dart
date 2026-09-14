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
/// Runs after `JumpSystem` in `installPlatformerSystems` so it has the
/// final say on `Velocity.y` this tick: while climbing (up/down held on
/// a ladder), gravity and any jump impulse from earlier this tick are
/// overridden with a direct climb velocity. Releasing both up and down
/// while still on the ladder holds the entity in place (`vel.y = 0`)
/// rather than gravity resuming mid-climb — freeing a jump off the
/// ladder still works, since `JumpSystem`'s own `vel.y` write happens
/// first and only `onLadder` + held vertical/idle input overrides it;
/// a jump fires by simply not being on `onLadder` (`grounded` isn't
/// required to leave a ladder horizontally and then jump normally).
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

    var vy = 0.0;
    if (input.isPressed(upAction)) vy -= controller.climbSpeed;
    if (input.isPressed(downAction)) vy += controller.climbSpeed;

    vel.y = vy;
    controller.grounded = false;
  }
}
