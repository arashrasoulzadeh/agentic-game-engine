import '../components/platformer_controller.dart';
import '../components/velocity.dart';
import '../system.dart';
import '../world.dart';

/// Consumes jump input. Deliberately separate from `PlatformerSystem`/
/// `TileCollisionSystem` and must run *after* both: grounded state can
/// come from either a `PlatformBody` or a tile, and checking
/// `jumpRequested` before both have had a chance to set `grounded` for
/// this tick would miss jumps off tile-only ground (an earlier version
/// had this bug — jump handling lived inside `PlatformerSystem` itself,
/// so grounding-via-tiles, resolved by a system that necessarily runs
/// after it, was never visible to that tick's jump check).
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
      if (controller.grounded && controller.jumpRequested) {
        final vel = velocities.get(entity);
        if (vel != null) {
          vel.y = -controller.jumpSpeed;
        }
        controller.grounded = false;
      }
      controller.jumpRequested = false;
    }
  }
}
