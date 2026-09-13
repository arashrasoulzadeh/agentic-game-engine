import 'package:engine_core/engine_core.dart';

import 'components/platformer_controller.dart';

/// Which face of an AABB a circle's overlap was resolved against, from
/// `resolveSolidCircleAabb` — `none` if there was no overlap at all.
/// `top` is what "grounded" reads; `left`/`right` are what wall-slide/
/// wall-jump read (see `PlatformerController.touchingWallLeft`/`Right`
/// — note the mapping is inverted: resolving against the AABB's *left*
/// face means the entity ended up positioned to the AABB's left, i.e.
/// there's a wall on the entity's *right*).
enum CollisionSide { none, top, bottom, left, right }

/// Shared circle-vs-AABB resolution, used by both `PlatformerSystem`
/// (for `PlatformBody` entities) and `TileCollisionSystem` (for
/// individual solid tiles) — same push-out-along-smallest-penetration-
/// axis logic either way, so it's factored out once rather than
/// duplicated and risking the two diverging.
///
/// Mutates [pos]/[vel] in place. Returns which face was resolved
/// against, so a caller can derive both "landed on top" (grounded) and
/// "touching a side" (wall contact) from the same call instead of two
/// separate checks.
CollisionSide resolveSolidCircleAabb({
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
  if (distSq >= radius * radius) return CollisionSide.none;

  final overlapLeft = (pos.x + radius) - left;
  final overlapRight = right - (pos.x - radius);
  final overlapTop = (pos.y + radius) - top;
  final overlapBottom = bottom - (pos.y - radius);
  final minOverlap =
      [overlapLeft, overlapRight, overlapTop, overlapBottom].reduce((a, b) => a < b ? a : b);

  if (minOverlap == overlapTop) {
    pos.y = top - radius;
    if (vel.y > 0) vel.y = 0;
    return CollisionSide.top;
  } else if (minOverlap == overlapBottom) {
    pos.y = bottom + radius;
    if (vel.y < 0) vel.y = 0;
    return CollisionSide.bottom;
  } else if (minOverlap == overlapLeft) {
    pos.x = left - radius;
    if (vel.x > 0) vel.x = 0;
    return CollisionSide.left;
  } else {
    pos.x = right + radius;
    if (vel.x < 0) vel.x = 0;
    return CollisionSide.right;
  }
}

/// Translates a `resolveSolidCircleAabb` result into `PlatformerController`
/// state — `grounded` for `top`, `touchingWallLeft`/`Right` for
/// `left`/`right` (note the inversion: resolved-against-the-AABB's-left
/// means the entity is touching a wall on its own *right* — see
/// `CollisionSide`'s doc comment), plus the wall-slide fall-speed clamp
/// while touching either side. Shared by `PlatformerSystem` (for
/// `PlatformBody`) and `TileCollisionSystem` (for solid tiles) so the
/// two can't diverge on what a side-touch means, same reasoning
/// `resolveSolidCircleAabb` itself is factored out once.
///
/// Doesn't touch `dt`/carry-along-a-moving-platform logic — that's
/// caller-specific (a `PlatformBody` can move, a tile grid effectively
/// can't), so it stays in each caller.
void applyCollisionSideToController({
  required CollisionSide side,
  required PlatformerController controller,
  required Velocity vel,
}) {
  switch (side) {
    case CollisionSide.top:
      controller.grounded = true;
    case CollisionSide.left:
      controller.touchingWallRight = true;
      _clampWallSlide(controller, vel);
    case CollisionSide.right:
      controller.touchingWallLeft = true;
      _clampWallSlide(controller, vel);
    case CollisionSide.bottom:
    case CollisionSide.none:
      break;
  }
}

void _clampWallSlide(PlatformerController controller, Velocity vel) {
  final maxFall = controller.wallSlideMaxFallSpeed;
  if (maxFall != null && vel.y > maxFall) vel.y = maxFall;
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
