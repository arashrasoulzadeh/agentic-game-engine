import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'platformer_controller.dart';

/// Lets an airborne entity grab and climb up onto the top of a wall
/// instead of always sliding/falling past it — opt-in via
/// `PlatformerController.ledgeGrabEnabled` (`false` default, a no-op
/// otherwise, same convention as every other feel field on
/// `PlatformerController`).
///
/// **Detecting a grab** (only checked while airborne — `!grounded` —
/// and touching a wall, i.e. `touchingWallLeft`/`touchingWallRight`,
/// both already resolved this tick by `PlatformerSystem`/
/// `TileCollisionSystem`): the tile directly beside the entity, in the
/// wall's direction, at the entity's own row must be solid (that's the
/// wall being touched), *and* the tile one row above it must be empty
/// (open headroom — this is what makes it specifically the wall's top
/// edge, not just any point partway up a tall wall), *and* the tile
/// directly above the entity's own row (same column as the entity)
/// must also be empty (room for the entity's own head, so mantling
/// won't shove it into solid geometry). This is a simplified,
/// tile-grid approximation deliberately in the same spirit as
/// `resolveSlopeCircleAabb`'s "walkable-surface simplification, not
/// true polygon physics" — it reads the *row* the entity's `Position`
/// falls into, not a sub-tile-precise contact point.
///
/// **While grabbing**: `Velocity` is frozen to `(0, 0)` every tick
/// (overriding gravity/input) until the player either mantles (holds
/// `up` or `jump`) or drops (holds `down`, releasing the grab and
/// letting gravity resume). Horizontal input has no effect while
/// hanging, matching a real ledge grab — you can't walk while gripping
/// a wall.
///
/// **Mantling**: teleports straight to `ledgeMantleTargetX/Y` — the
/// standing position one tile up and half a tile forward, computed
/// once at the moment the grab started (see `PlatformerController`'s
/// doc comment on those fields) — rather than simulating a climb
/// animation's actual motion; a game wanting a smoother visual can
/// tween its own sprite toward the entity's `Position` after the
/// teleport, the same way any other instant-position-change already
/// works in this engine (e.g. a respawn).
///
/// Runs after `JumpSystem`/`LadderSystem` in `installPlatformerSystems`
/// so a jump input that also happens to satisfy the grab condition
/// this tick results in a grab, not a jump — grabbing always takes
/// priority once its conditions are met.
class LedgeGrabSystem implements System {
  final EntityId entity;
  final String upAction;
  final String downAction;
  final String jumpAction;

  LedgeGrabSystem(
    this.entity, {
    this.upAction = 'up',
    this.downAction = 'down',
    this.jumpAction = 'jump',
  });

  @override
  String get name => 'ledgeGrab';

  @override
  void update(World world, double dt) {
    final controller = world.storeOf<PlatformerController>().get(entity);
    if (controller == null || !controller.ledgeGrabEnabled) return;

    if (controller.hitstunSeconds > 0) {
      // A knockback impulse while hanging should actually knock the
      // entity back, not leave it stuck frozen mid-air -- release the
      // grab outright rather than trying to reconcile the two.
      controller.ledgeGrabbing = false;
      return;
    }

    final pos = world.storeOf<Position>().get(entity);
    final vel = world.storeOf<Velocity>().get(entity);
    final input = world.storeOf<InputState>().get(entity);
    if (pos == null || vel == null || input == null) return;

    if (controller.ledgeGrabbing) {
      if (input.isPressed(upAction) || input.isPressed(jumpAction)) {
        pos.x = controller.ledgeMantleTargetX;
        pos.y = controller.ledgeMantleTargetY;
        vel.x = 0;
        vel.y = 0;
        controller.grounded = true;
        controller.ledgeGrabbing = false;
        return;
      }
      if (input.isPressed(downAction)) {
        controller.ledgeGrabbing = false;
        return;
      }
      vel.x = 0;
      vel.y = 0;
      return;
    }

    if (controller.grounded) return;
    if (!controller.touchingWallLeft && !controller.touchingWallRight) return;

    final collider = world.storeOf<Collider>().get(entity);
    if (collider == null) return;

    final direction = controller.touchingWallRight ? 1 : -1;
    final tileMaps = world.storeOf<TileMap>();
    final positions = world.storeOf<Position>();

    for (var m = 0; m < tileMaps.length; m++) {
      final mapEntity = tileMaps.entityAt(m);
      final map = tileMaps.denseAt(m);
      final origin = positions.get(mapEntity) ?? Position(0, 0);

      final wallX = pos.x + direction * (collider.radius + 1);
      final wallCol = ((wallX - origin.x) / map.tileWidth).floor();
      final entityCol = ((pos.x - origin.x) / map.tileWidth).floor();
      final entityRow = ((pos.y - origin.y) / map.tileHeight).floor();

      final wallHere = map.isSolid(wallCol, entityRow);
      final headroomAboveWall = !map.isSolid(wallCol, entityRow - 1);
      final headroomAboveSelf = !map.isSolid(entityCol, entityRow - 1);
      if (!wallHere || !headroomAboveWall || !headroomAboveSelf) continue;

      final ledgeTopY = origin.y + entityRow * map.tileHeight;
      controller.ledgeGrabbing = true;
      controller.grounded = false;
      controller.ledgeMantleTargetX = pos.x + direction * (map.tileWidth * 0.6);
      controller.ledgeMantleTargetY = ledgeTopY - collider.radius;
      pos.y = ledgeTopY + collider.radius;
      vel.x = 0;
      vel.y = 0;
      return;
    }
  }
}
