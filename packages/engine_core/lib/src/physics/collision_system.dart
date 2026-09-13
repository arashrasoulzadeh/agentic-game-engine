import '../ecs/component_store.dart';
import 'collider.dart';
import 'position.dart';
import 'velocity.dart';
import '../ecs/entity.dart';
import 'spatial_hash.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';

/// Cell size to fall back on when there's nothing to size from yet (no
/// `Collider`s in the world this tick) -- matches this system's
/// original fixed default, so an empty/near-empty world behaves the
/// same as before this became auto-sizing.
const _defaultCellSize = 24.0;

class CollisionEvent {
  final EntityId a, b;
  CollisionEvent(this.a, this.b);
}

/// Broad-phase via spatial hash, narrow-phase via circle distance check.
/// On overlap: swaps velocities (cheap elastic-ish response) and emits a
/// CollisionEvent so other systems (damage, sfx) can react without this
/// system knowing about them.
class CollisionSystem implements System {
  /// Fixed cell size, if given. Leave `null` (the default) to auto-size
  /// it every tick instead, from `2 * ` the largest `Collider.radius`
  /// currently in the world — the minimum cell size for which the
  /// broad-phase's "check same + adjacent cells only" search can never
  /// miss a colliding pair (two circles can only overlap if the
  /// distance between centers is `<= radiusA + radiusB`, which is
  /// `<= 2 * maxRadius` whenever both radii are at most `maxRadius`).
  ///
  /// A single fixed cell size (this system's original design) is a
  /// correctness *and* performance trap for anything other than
  /// roughly-uniform, roughly-24-radius colliders: too small for a
  /// bigger collider risks silently missing real collisions; too big
  /// for a swarm of small ones (e.g. bullets/coins) packs far more
  /// entities per cell than necessary, and `forEachNearbyPair`'s
  /// per-cell cost is quadratic in that count — confirmed by
  /// `collision_system_benchmark.dart`, which found ~193x slower for a
  /// 5x entity increase at high density with the old fixed default.
  /// Pass an explicit value only if you've profiled a specific scene
  /// and know better than the auto-sizing.
  final double? cellSize;
  CollisionSystem({this.cellSize});

  @override
  String get name => 'collision';

  @override
  void update(World world, double dt) {
    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();
    final colliders = world.storeOf<Collider>();

    final hash = SpatialHash(cellSize: _resolveCellSize(colliders), worldWidth: world.width);
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

  double _resolveCellSize(ComponentStore<Collider> colliders) {
    final fixed = cellSize;
    if (fixed != null) return fixed;

    var maxRadius = 0.0;
    for (var i = 0; i < colliders.length; i++) {
      final radius = colliders.denseAt(i).radius;
      if (radius > maxRadius) maxRadius = radius;
    }
    return maxRadius > 0 ? maxRadius * 2 : _defaultCellSize;
  }
}
