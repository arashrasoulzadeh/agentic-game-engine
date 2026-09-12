import '../components/collider.dart';
import '../components/position.dart';
import '../components/velocity.dart';
import '../system.dart';
import '../world.dart';

/// Integrates Position by Velocity and bounces entities off world bounds.
/// Iterates the smaller of the two stores' dense arrays for cache-friendly
/// access, skipping entities that lack the other component.
class MovementSystem implements System {
  @override
  String get name => 'movement';

  @override
  void update(World world, double dt) {
    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();
    final colliders = world.storeOf<Collider>();

    for (var i = 0; i < velocities.length; i++) {
      final entity = velocities.entityAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;
      final vel = velocities.denseAt(i);
      final radius = colliders.get(entity)?.radius ?? 0;

      pos.x += vel.x * dt;
      pos.y += vel.y * dt;

      if (pos.x - radius < 0 || pos.x + radius > world.width) {
        vel.x = -vel.x;
        pos.x = pos.x.clamp(radius, world.width - radius);
      }
      if (pos.y - radius < 0 || pos.y + radius > world.height) {
        vel.y = -vel.y;
        pos.y = pos.y.clamp(radius, world.height - radius);
      }
    }
  }
}
