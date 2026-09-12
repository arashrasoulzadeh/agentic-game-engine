import 'package:engine_core/engine_core.dart';

import '../components/gravity.dart';
import '../components/platformer_controller.dart';

/// Accelerates `Velocity.y` downward for every entity with a `Gravity`
/// component. Skips entities `PlatformerSystem` has already marked
/// grounded this tick — otherwise gravity re-accumulates into the floor
/// every frame and fights the ground snap.
class GravitySystem implements System {
  final double gravity;

  GravitySystem({this.gravity = 980});

  @override
  String get name => 'gravity';

  @override
  void update(World world, double dt) {
    final gravities = world.storeOf<Gravity>();
    final velocities = world.storeOf<Velocity>();
    final controllers = world.storeOf<PlatformerController>();

    for (var i = 0; i < gravities.length; i++) {
      final entity = gravities.entityAt(i);
      final vel = velocities.get(entity);
      if (vel == null) continue;

      final controller = controllers.get(entity);
      if (controller != null && controller.grounded) continue;

      vel.y += gravity * gravities.denseAt(i).scale * dt;
    }
  }
}
