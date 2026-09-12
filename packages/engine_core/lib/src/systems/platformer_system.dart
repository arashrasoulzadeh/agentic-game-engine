import '../components/collider.dart';
import '../components/platform_body.dart';
import '../components/platformer_controller.dart';
import '../components/position.dart';
import '../components/velocity.dart';
import '../system.dart';
import '../world.dart';

/// Ground detection, jump, and platform collision for entities with a
/// `PlatformerController`. Runs after `MovementSystem`/`GravitySystem`
/// so it resolves this tick's already-integrated position.
///
/// Two platform kinds, both via `PlatformBody`:
/// - **One-way** (`oneWay: true`): landable from above only, while
///   falling/resting — never blocks from below or the sides (classic
///   jump-through platform). Detected by "foot crossed the platform's
///   top surface this frame while moving downward", not full AABB
///   overlap, so jumping up through one from below never catches it.
/// - **Solid** (`oneWay: false`): full circle-vs-AABB resolution,
///   pushed out along whichever axis has the smallest penetration —
///   blocks landing, side contact, and hitting the underside.
class PlatformerSystem implements System {
  @override
  String get name => 'platformer';

  @override
  void update(World world, double dt) {
    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();
    final colliders = world.storeOf<Collider>();
    final controllers = world.storeOf<PlatformerController>();
    final platformBodies = world.storeOf<PlatformBody>();

    for (var i = 0; i < controllers.length; i++) {
      final entity = controllers.entityAt(i);
      final controller = controllers.denseAt(i);
      final pos = positions.get(entity);
      final vel = velocities.get(entity);
      final collider = colliders.get(entity);
      if (pos == null || vel == null || collider == null) continue;

      controller.grounded = false;

      for (var j = 0; j < platformBodies.length; j++) {
        final platformEntity = platformBodies.entityAt(j);
        if (platformEntity == entity) continue;
        final platform = platformBodies.denseAt(j);
        final platformPos = positions.get(platformEntity);
        if (platformPos == null) continue;

        final left = platformPos.x - platform.width / 2;
        final right = platformPos.x + platform.width / 2;
        final top = platformPos.y - platform.height / 2;
        final bottom = platformPos.y + platform.height / 2;

        if (platform.oneWay) {
          if (vel.y < 0) continue;
          final withinX = pos.x >= left && pos.x <= right;
          final footY = pos.y + collider.radius;
          final prevFootY = footY - vel.y * dt;
          if (withinX && prevFootY <= top + 0.01 && footY >= top) {
            pos.y = top - collider.radius;
            vel.y = 0;
            controller.grounded = true;
          }
          continue;
        }

        final closestX = pos.x.clamp(left, right);
        final closestY = pos.y.clamp(top, bottom);
        final dx = pos.x - closestX;
        final dy = pos.y - closestY;
        final distSq = dx * dx + dy * dy;
        if (distSq >= collider.radius * collider.radius) continue;

        final overlapLeft = (pos.x + collider.radius) - left;
        final overlapRight = right - (pos.x - collider.radius);
        final overlapTop = (pos.y + collider.radius) - top;
        final overlapBottom = bottom - (pos.y - collider.radius);
        final minOverlap = [overlapLeft, overlapRight, overlapTop, overlapBottom]
            .reduce((a, b) => a < b ? a : b);

        if (minOverlap == overlapTop) {
          pos.y = top - collider.radius;
          if (vel.y > 0) vel.y = 0;
          controller.grounded = true;
        } else if (minOverlap == overlapBottom) {
          pos.y = bottom + collider.radius;
          if (vel.y < 0) vel.y = 0;
        } else if (minOverlap == overlapLeft) {
          pos.x = left - collider.radius;
          if (vel.x > 0) vel.x = 0;
        } else {
          pos.x = right + collider.radius;
          if (vel.x < 0) vel.x = 0;
        }
      }

      if (controller.grounded && controller.jumpRequested) {
        vel.y = -controller.jumpSpeed;
        controller.grounded = false;
      }
      controller.jumpRequested = false;
    }
  }
}
