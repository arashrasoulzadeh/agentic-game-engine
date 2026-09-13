import 'package:engine_core/engine_core.dart';

import '../components/platformer_controller.dart';

/// Consumes jump input — grounded jumps (with optional coyote time/jump
/// buffering), air jumps (double jump, via `maxAirJumps`), and wall
/// jumps (via `wallJumpPushSpeed`), all opt-in per `PlatformerController`
/// field, all defaulting to the original strict "grounded and pressed
/// this exact tick" behavior. Deliberately separate from
/// `PlatformerSystem`/`TileCollisionSystem` and must run *after* both:
/// grounded/wall state can come from either a `PlatformBody` or a tile,
/// and checking it before both have had a chance to set it for this
/// tick would miss jumps off tile-only ground (an earlier version had
/// this bug — jump handling lived inside `PlatformerSystem` itself, so
/// grounding-via-tiles, resolved by a system that necessarily runs
/// after it, was never visible to that tick's jump check).
///
/// Every tick, regardless of whether a jump fires:
/// - `timeSinceGrounded` resets to `0` if `grounded` is true this tick,
///   else increments by `dt`. A grounded/coyote jump can fire while
///   `timeSinceGrounded <= coyoteTimeSeconds`.
/// - `timeSinceJumpPressed` resets to `0` if `jumpRequested` is true
///   this tick, else increments by `dt`. A jump only fires while
///   `timeSinceJumpPressed <= jumpBufferSeconds`.
/// - `airJumpsUsed`/`dashUsed` reset to `0`/`false` the tick `grounded`
///   becomes true (a fresh set of air actions per ground contact).
///
/// Priority when a jump is "wanted" (buffered) and not a plain grounded
/// jump: wall jump (if touching a wall and `wallJumpPushSpeed > 0`),
/// then an air jump (if `airJumpsUsed < maxAirJumps`). At most one kind
/// fires per tick.
class JumpSystem implements System {
  @override
  String get name => 'jump';

  @override
  void update(World world, double dt) {
    final controllers = world.storeOf<PlatformerController>();
    final velocities = world.storeOf<Velocity>();

    for (var i = 0; i < controllers.length; i++) {
      final entity = controllers.entityAt(i);
      final controller = controllers.denseAt(i);
      final vel = velocities.get(entity);

      if (controller.grounded) {
        controller.timeSinceGrounded = 0;
        controller.airJumpsUsed = 0;
        controller.dashUsed = false;
      } else {
        controller.timeSinceGrounded += dt;
      }

      if (controller.jumpRequested) {
        controller.timeSinceJumpPressed = 0;
      } else {
        controller.timeSinceJumpPressed += dt;
      }

      final canGroundJump = controller.timeSinceGrounded <= controller.coyoteTimeSeconds;
      final jumpWanted = controller.timeSinceJumpPressed <= controller.jumpBufferSeconds;

      if (vel != null && jumpWanted) {
        if (canGroundJump) {
          vel.y = -controller.jumpSpeed;
          _consumeJump(controller);
        } else if ((controller.touchingWallLeft || controller.touchingWallRight) &&
            controller.wallJumpPushSpeed > 0) {
          vel.y = -controller.jumpSpeed;
          // Push away from whichever wall is touched -- touching a wall
          // on this entity's left means push right, and vice versa.
          vel.x = controller.wallJumpPushSpeed *
              (controller.touchingWallLeft ? 1 : -1);
          _consumeJump(controller);
        } else if (controller.airJumpsUsed < controller.maxAirJumps) {
          vel.y = -controller.jumpSpeed;
          controller.airJumpsUsed++;
          _consumeJump(controller);
        }
      }

      controller.jumpRequested = false;
    }
  }

  /// Pushes both timers past their windows so the same buffered press/
  /// coyote window can't fire a second jump next tick.
  void _consumeJump(PlatformerController controller) {
    controller.grounded = false;
    controller.timeSinceGrounded = controller.coyoteTimeSeconds + 1;
    controller.timeSinceJumpPressed = controller.jumpBufferSeconds + 1;
  }
}
