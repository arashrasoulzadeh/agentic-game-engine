import 'components/position.dart';
import 'entity.dart';
import 'world.dart';

/// Read-only window onto a [World] for runtime agents/NPC behaviors.
/// Deliberately has no mutation methods — a `Behavior` only ever sees a
/// `WorldView`, never the real `World`, so an agent-authored behavior
/// can't corrupt simulation state directly; it can only return an
/// [Action] for `AISystem` to apply.
class WorldView {
  final World _world;

  WorldView(this._world);

  double get width => _world.width;
  double get height => _world.height;
  int get tick => _world.tick;

  T? component<T>(EntityId entity) => _world.storeOf<T>().get(entity);

  bool hasComponent<T>(EntityId entity) => _world.storeOf<T>().has(entity);

  /// All entities carrying component [T], in no particular order.
  Iterable<EntityId> entitiesWith<T>() sync* {
    final store = _world.storeOf<T>();
    for (var i = 0; i < store.length; i++) {
      yield store.entityAt(i);
    }
  }

  /// The closest entity with a `Position` to ([x], [y]), or null if none
  /// qualify. Linear scan — fine at the entity counts a single AI
  /// query needs; reach for `SpatialHash` directly in a System if you
  /// need this at scale across many agents per tick.
  EntityId? nearestWithPosition(
    double x,
    double y, {
    EntityId? exclude,
    double? maxDistance,
  }) {
    final positions = _world.storeOf<Position>();
    EntityId? best;
    var bestDistSq = double.infinity;
    final maxDistSq =
        maxDistance == null ? double.infinity : maxDistance * maxDistance;

    for (var i = 0; i < positions.length; i++) {
      final id = positions.entityAt(i);
      if (id == exclude) continue;
      final p = positions.denseAt(i);
      final dx = p.x - x;
      final dy = p.y - y;
      final distSq = dx * dx + dy * dy;
      if (distSq <= maxDistSq && distSq < bestDistSq) {
        bestDistSq = distSq;
        best = id;
      }
    }
    return best;
  }
}
