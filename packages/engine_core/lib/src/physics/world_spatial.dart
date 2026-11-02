import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'raycast.dart';
import 'position.dart';

/// Spatial questions on [World] without wiring a [SpatialHash] by hand.
extension WorldSpatial on World {
  /// The nearest collider a ray from ([fromX], [fromY]) to ([toX], [toY])
  /// hits, or null; [exclude] skips the caster. See [raycastEntities].
  RaycastHit? raycast(
    double fromX,
    double fromY,
    double toX,
    double toY, {
    EntityId? exclude,
  }) => raycastEntities(
    this,
    fromX: fromX,
    fromY: fromY,
    toX: toX,
    toY: toY,
    exclude: exclude,
  );

  /// Entities with a [Position] within [radius] of ([x], [y]), nearest first.
  ///
  /// A plain scan of every positioned entity (O(n)), which is fine for the
  /// occasional "what is near the player" question; per-frame all-pairs work
  /// belongs in a system using a `SpatialHash`. [exclude] skips one entity.
  List<EntityId> findNear(
    double x,
    double y,
    double radius, {
    EntityId? exclude,
  }) {
    final positions = componentsOf<Position>();
    final limit = radius * radius;
    final hits = <(double, EntityId)>[];
    for (var i = 0; i < positions.length; i++) {
      final id = positions.entityAt(i);
      if (id == exclude) continue;
      final p = positions.denseAt(i);
      final dx = p.x - x, dy = p.y - y;
      final d = dx * dx + dy * dy;
      if (d <= limit) hits.add((d, id));
    }
    hits.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return [for (final h in hits) h.$2];
  }
}
