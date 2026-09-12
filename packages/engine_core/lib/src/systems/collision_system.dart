import '../components/collider.dart';
import '../components/position.dart';
import '../components/velocity.dart';
import '../entity.dart';
import '../spatial_hash.dart';
import '../system.dart';
import '../world.dart';

class CollisionEvent {
  final EntityId a, b;
  CollisionEvent(this.a, this.b);
}

/// Broad-phase via spatial hash, narrow-phase via circle distance check.
/// On overlap: swaps velocities (cheap elastic-ish response) and emits a
/// CollisionEvent so other systems (damage, sfx) can react without this
/// system knowing about them.
class CollisionSystem implements System {
  final double cellSize;
  CollisionSystem({this.cellSize = 24});

  @override
  String get name => 'collision';

  @override
  void update(World world, double dt) {
    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();
    final colliders = world.storeOf<Collider>();

    final hash = SpatialHash(cellSize: cellSize, worldWidth: world.width);
    for (var i = 0; i < colliders.length; i++) {
      final entity = colliders.entityAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;
      hash.insert(entity, pos.x, pos.y);
    }

    hash.forEachNearbyPair((a, b) {
      final posA = positions.get(a);
      final posB = positions.get(b);
      final colA = colliders.get(a);
      final colB = colliders.get(b);
      if (posA == null || posB == null || colA == null || colB == null) {
        return;
      }

      final dx = posB.x - posA.x;
      final dy = posB.y - posA.y;
      final minDist = colA.radius + colB.radius;
      final distSq = dx * dx + dy * dy;
      if (distSq >= minDist * minDist || distSq < 0.0001) return;

      final velA = velocities.get(a);
      final velB = velocities.get(b);
      if (velA != null && velB != null) {
        final tmpX = velA.x, tmpY = velA.y;
        velA.x = velB.x;
        velA.y = velB.y;
        velB.x = tmpX;
        velB.y = tmpY;
      }

      world.events.emit(CollisionEvent(a, b));
    });
  }
}
