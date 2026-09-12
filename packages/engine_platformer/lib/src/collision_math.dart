import 'package:engine_core/engine_core.dart';

/// Shared circle-vs-AABB resolution, used by both `PlatformerSystem`
/// (for `PlatformBody` entities) and `TileCollisionSystem` (for
/// individual solid tiles) — same push-out-along-smallest-penetration-
/// axis logic either way, so it's factored out once rather than
/// duplicated and risking the two diverging.
///
/// Mutates [pos]/[vel] in place. Returns whether this resolution counts
/// as "landed on top" (the caller sets `grounded` from that).
bool resolveSolidCircleAabb({
  required Position pos,
  required Velocity vel,
  required double radius,
  required double left,
  required double right,
  required double top,
  required double bottom,
}) {
  final closestX = pos.x.clamp(left, right);
  final closestY = pos.y.clamp(top, bottom);
  final dx = pos.x - closestX;
  final dy = pos.y - closestY;
  final distSq = dx * dx + dy * dy;
  if (distSq >= radius * radius) return false;

  final overlapLeft = (pos.x + radius) - left;
  final overlapRight = right - (pos.x - radius);
  final overlapTop = (pos.y + radius) - top;
  final overlapBottom = bottom - (pos.y - radius);
  final minOverlap =
      [overlapLeft, overlapRight, overlapTop, overlapBottom].reduce((a, b) => a < b ? a : b);

  if (minOverlap == overlapTop) {
    pos.y = top - radius;
    if (vel.y > 0) vel.y = 0;
    return true;
  } else if (minOverlap == overlapBottom) {
    pos.y = bottom + radius;
    if (vel.y < 0) vel.y = 0;
  } else if (minOverlap == overlapLeft) {
    pos.x = left - radius;
    if (vel.x > 0) vel.x = 0;
  } else {
    pos.x = right + radius;
    if (vel.x < 0) vel.x = 0;
  }
  return false;
}

/// One-way ("landable from above only") resolution: catches an entity
/// only if it's falling/resting and its foot crossed [top] this frame —
/// never blocks from below or the sides. Returns whether it landed.
bool resolveOneWayCircleAabb({
  required Position pos,
  required Velocity vel,
  required double radius,
  required double dt,
  required double left,
  required double right,
  required double top,
}) {
  if (vel.y < 0) return false;
  if (pos.x < left || pos.x > right) return false;

  final footY = pos.y + radius;
  final prevFootY = footY - vel.y * dt;
  if (prevFootY <= top + 0.01 && footY >= top) {
    pos.y = top - radius;
    vel.y = 0;
    return true;
  }
  return false;
}
