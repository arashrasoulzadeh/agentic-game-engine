import 'dart:math';

import 'components/collider.dart';
import 'components/position.dart';
import 'components/tile_map.dart';
import 'entity.dart';
import 'world.dart';

/// Where a ray first hit something — a `TileMap` cell (`raycastTileMap`)
/// or an entity (`raycastEntities`). [entity] is set only for the
/// latter; a tile hit has no entity of its own (the `TileMap`'s own
/// entity isn't what was "hit," a specific cell was).
class RaycastHit {
  final double x;
  final double y;
  final double distance;
  final EntityId? entity;

  RaycastHit({required this.x, required this.y, required this.distance, this.entity});
}

/// Walks the grid cells a ray from ([fromX], [fromY]) to ([toX], [toY])
/// passes through, in order (a standard grid-DDA / "Amanatides & Woo"
/// traversal — checks every cell the ray actually crosses, so it can't
/// tunnel through a thin wall the way naively sampling points along the
/// segment at fixed intervals could), returning the first solid tile it
/// hits, or `null` if the ray reaches [toX]/[toY] without hitting one.
/// [origin] is the `TileMap` entity's own `Position` (the grid's
/// world-space top-left corner) — the same value `TileCollisionSystem`
/// reads.
///
/// Only `solidTileIds` block by default; pass [blockOneWay] to also
/// stop at a one-way tile (rarely what you want for a line-of-sight
/// check, since a one-way platform is meant to be seen/shot through
/// from below — off by default for that reason). Slope tiles never
/// block a raycast — they're a walkable-surface concept (see
/// `engine_platformer`'s `resolveSlopeCircleAabb`), not a wall.
RaycastHit? raycastTileMap(
  TileMap map,
  Position origin,
  double fromX,
  double fromY,
  double toX,
  double toY, {
  bool blockOneWay = false,
}) {
  final localFromX = fromX - origin.x;
  final localFromY = fromY - origin.y;
  final dx = (toX - origin.x) - localFromX;
  final dy = (toY - origin.y) - localFromY;
  if (dx == 0 && dy == 0) return null;

  var col = (localFromX / map.tileWidth).floor();
  var row = (localFromY / map.tileHeight).floor();
  final endCol = ((toX - origin.x) / map.tileWidth).floor();
  final endRow = ((toY - origin.y) / map.tileHeight).floor();

  final stepX = dx > 0 ? 1 : (dx < 0 ? -1 : 0);
  final stepY = dy > 0 ? 1 : (dy < 0 ? -1 : 0);

  double tMaxX, tDeltaX;
  if (dx != 0) {
    final nextBoundaryX = (stepX > 0 ? col + 1 : col) * map.tileWidth;
    tMaxX = (nextBoundaryX - localFromX) / dx;
    tDeltaX = map.tileWidth / dx.abs();
  } else {
    tMaxX = double.infinity;
    tDeltaX = double.infinity;
  }
  double tMaxY, tDeltaY;
  if (dy != 0) {
    final nextBoundaryY = (stepY > 0 ? row + 1 : row) * map.tileHeight;
    tMaxY = (nextBoundaryY - localFromY) / dy;
    tDeltaY = map.tileHeight / dy.abs();
  } else {
    tMaxY = double.infinity;
    tDeltaY = double.infinity;
  }

  final totalDistance = sqrt(dx * dx + dy * dy);
  var t = 0.0;
  while (true) {
    final tileId = map.tileAt(col, row);
    final blocks = map.solidTileIds.contains(tileId) || (blockOneWay && map.oneWayTileIds.contains(tileId));
    if (blocks) {
      return RaycastHit(x: fromX + dx * t, y: fromY + dy * t, distance: totalDistance * t);
    }
    if (col == endCol && row == endRow) return null;
    if (tMaxX < tMaxY) {
      t = tMaxX;
      if (t > 1) return null;
      col += stepX;
      tMaxX += tDeltaX;
    } else {
      t = tMaxY;
      if (t > 1) return null;
      row += stepY;
      tMaxY += tDeltaY;
    }
  }
}

/// Finds the nearest `Collider` entity a ray from ([fromX], [fromY]) to
/// ([toX], [toY]) intersects (standard ray-vs-circle math), or `null`
/// if it misses everything. Pass [exclude] to skip an entity (typically
/// the one casting the ray, so it doesn't hit itself).
RaycastHit? raycastEntities(
  World world, {
  required double fromX,
  required double fromY,
  required double toX,
  required double toY,
  EntityId? exclude,
}) {
  final positions = world.storeOf<Position>();
  final colliders = world.storeOf<Collider>();

  final dx = toX - fromX;
  final dy = toY - fromY;
  final lenSq = dx * dx + dy * dy;
  if (lenSq < 1e-9) return null;

  RaycastHit? best;
  var bestT = double.infinity;
  for (var i = 0; i < colliders.length; i++) {
    final entity = colliders.entityAt(i);
    if (entity == exclude) continue;
    final pos = positions.get(entity);
    if (pos == null) continue;
    final radius = colliders.denseAt(i).radius;

    final t = _raySphereT(fromX, fromY, dx, dy, lenSq, pos, radius);
    if (t != null && t < bestT) {
      bestT = t;
      best = RaycastHit(
        x: fromX + dx * t,
        y: fromY + dy * t,
        distance: sqrt(lenSq) * t,
        entity: entity,
      );
    }
  }
  return best;
}

/// The segment-parameter `t` (0..1 along `from` -> `from + (dx,dy)`)
/// where the ray first enters [center]'s circle of [radius], or `null`
/// if it never does (including entirely behind `from` or past the
/// segment's end).
double? _raySphereT(
  double fromX,
  double fromY,
  double dx,
  double dy,
  double lenSq,
  Position center,
  double radius,
) {
  final ocx = fromX - center.x;
  final ocy = fromY - center.y;
  final b = 2 * (ocx * dx + ocy * dy);
  final c = ocx * ocx + ocy * ocy - radius * radius;
  final discriminant = b * b - 4 * lenSq * c;
  if (discriminant < 0) return null;

  final sqrtDisc = sqrt(discriminant);
  var t = (-b - sqrtDisc) / (2 * lenSq);
  if (t < 0) t = (-b + sqrtDisc) / (2 * lenSq); // `from` may already be inside the circle
  if (t < 0 || t > 1) return null;
  return t;
}
