import 'package:engine_core/engine_core.dart';

import '../collision_math.dart';
import '../components/platformer_controller.dart';

/// Ground detection and collision against `TileMap` grids, mirroring
/// `PlatformerSystem` but for tile-based level geometry — including
/// `TileMap.slopeUpRightTileIds`/`slopeUpLeftTileIds` ramps, which have
/// no `PlatformBody` equivalent (see `resolveSlopeCircleAabb`'s doc
/// comment for what "ramp" means here). Only checks the small range of
/// tiles overlapping each entity's bounding box (not the whole grid) —
/// the actual broad-phase for tile collision.
///
/// Never resets `controller.grounded`/`touchingWallLeft`/
/// `touchingWallRight` — `PlatformerSystem` owns that reset. This
/// system only ever sets them additively, so running both in either
/// order before `JumpSystem` is safe.
class TileCollisionSystem implements System {
  @override
  String get name => 'tileCollision';

  @override
  void update(World world, double dt) {
    final tileMaps = world.storeOf<TileMap>();
    if (tileMaps.length == 0) return;

    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();
    final colliders = world.storeOf<Collider>();
    final controllers = world.storeOf<PlatformerController>();

    for (var m = 0; m < tileMaps.length; m++) {
      final mapEntity = tileMaps.entityAt(m);
      final map = tileMaps.denseAt(m);
      final origin = positions.get(mapEntity) ?? Position(0, 0);

      for (var i = 0; i < controllers.length; i++) {
        final entity = controllers.entityAt(i);
        if (entity == mapEntity) continue;
        final controller = controllers.denseAt(i);
        final pos = positions.get(entity);
        final vel = velocities.get(entity);
        final collider = colliders.get(entity);
        if (pos == null || vel == null || collider == null) continue;

        final minCol = ((pos.x - collider.radius - origin.x) / map.tileWidth).floor();
        final maxCol = ((pos.x + collider.radius - origin.x) / map.tileWidth).ceil();
        final minRow = ((pos.y - collider.radius - origin.y) / map.tileHeight).floor();
        final maxRow = ((pos.y + collider.radius - origin.y) / map.tileHeight).ceil();

        for (var row = minRow; row <= maxRow; row++) {
          for (var col = minCol; col <= maxCol; col++) {
            final tileId = map.tileAt(col, row);
            if (tileId == 0) continue;

            final left = origin.x + col * map.tileWidth;
            final top = origin.y + row * map.tileHeight;
            final right = left + map.tileWidth;
            final bottom = top + map.tileHeight;

            if (map.oneWayTileIds.contains(tileId)) {
              if (resolveOneWayCircleAabb(
                pos: pos,
                vel: vel,
                radius: collider.radius,
                dt: dt,
                left: left,
                right: right,
                top: top,
              )) {
                controller.grounded = true;
              }
            } else if (map.solidTileIds.contains(tileId)) {
              final side = resolveSolidCircleAabb(
                pos: pos,
                vel: vel,
                radius: collider.radius,
                left: left,
                right: right,
                top: top,
                bottom: bottom,
              );
              applyCollisionSideToController(side: side, controller: controller, vel: vel);
            } else if (map.slopeUpRightTileIds.contains(tileId) ||
                map.slopeUpLeftTileIds.contains(tileId)) {
              if (resolveSlopeCircleAabb(
                pos: pos,
                vel: vel,
                radius: collider.radius,
                left: left,
                right: right,
                top: top,
                bottom: bottom,
                ascendingRight: map.slopeUpRightTileIds.contains(tileId),
              )) {
                controller.grounded = true;
              }
            }
          }
        }
      }
    }
  }
}
