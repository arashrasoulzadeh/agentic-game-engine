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
/// A platform's vertical motion already carries a rider "for free": the
/// AABB it's resolved against is recomputed from the platform's current
/// `Position` every tick, so a rider resting on top tracks a rising/
/// falling platform automatically. Horizontal motion doesn't — nothing
/// about the resolution otherwise touches a resting entity's `x` — so a
/// platform entity that also has a `Velocity` (add one, and move it
/// with `MovementSystem`, a `Tween`, or your own system — this doesn't
/// care how) has that `Velocity.x * dt` added directly to a rider's
/// `Position.x` the tick it lands on it, carrying it along
/// horizontally too. This only runs on the tick collision actually
/// resolves "landed on top," so it can't push a rider that isn't
/// actually standing on the platform.
///
/// Resets `controller.grounded`/`touchingWallLeft`/`touchingWallRight`
/// to `false` at the start of each entity's processing — the single
/// reset point. `TileCollisionSystem` (if present) runs after this and
/// only ever sets them additively; it never resets them, so
/// registration order between the two doesn't matter for correctness
/// as long as both run before `JumpSystem`.
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
      controller.touchingWallLeft = false;
      controller.touchingWallRight = false;

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

        bool landedOnThis;
        if (platform.oneWay) {
          landedOnThis = resolveOneWayCircleAabb(
            pos: pos,
            vel: vel,
            radius: collider.radius,
            dt: dt,
            left: left,
            right: right,
            top: top,
          );
          if (landedOnThis) controller.grounded = true;
        } else {
          final side = resolveSolidCircleAabb(
            pos: pos,
            vel: vel,
            radius: collider.radius,
            left: left,
            right: right,
            top: top,
            bottom: bottom,
          );
          landedOnThis = side == CollisionSide.top;
          applyCollisionSideToController(side: side, controller: controller, vel: vel);
        }

        if (landedOnThis) {
          final platformVel = velocities.get(platformEntity);
          if (platformVel != null) pos.x += platformVel.x * dt;
        }
      }
    }
  }
}
