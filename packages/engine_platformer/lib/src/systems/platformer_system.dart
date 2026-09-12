import 'package:engine_core/engine_core.dart';

import '../collision_math.dart';
import '../components/platform_body.dart';
import '../components/platformer_controller.dart';

/// Ground detection and platform collision (not jump — see `JumpSystem`)
/// for entities with a `PlatformerController`, against `PlatformBody`
/// entities. Runs after `MovementSystem`/`GravitySystem` so it resolves
/// this tick's already-integrated position.
///
/// Two platform kinds, both via `PlatformBody`:
/// - **One-way** (`oneWay: true`): landable from above only, while
///   falling/resting — never blocks from below or the sides.
/// - **Solid** (`oneWay: false`): full circle-vs-AABB resolution.
///
/// Resets `controller.grounded = false` at the start of each entity's
/// processing — the single reset point. `TileCollisionSystem` (if
/// present) runs after this and only ever sets `grounded = true`
/// additively; it never resets it, so registration order between the
/// two doesn't matter for correctness as long as both run before
/// `JumpSystem`.
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
        } else {
          if (resolveSolidCircleAabb(
            pos: pos,
            vel: vel,
            radius: collider.radius,
            left: left,
            right: right,
            top: top,
            bottom: bottom,
          )) {
            controller.grounded = true;
          }
        }
      }
    }
  }
}
