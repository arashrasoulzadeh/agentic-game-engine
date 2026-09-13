import '../physics/position.dart';
import '../physics/tile_map.dart';
import 'entity.dart';
import '../physics/raycast.dart';
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

  /// All entities carrying both [A] and [B], in no particular order —
  /// "entities with both X and Y" otherwise means hand-nesting a loop
  /// plus `hasComponent` checks at every call site. Scans whichever of
  /// the two stores is currently smaller and checks the other via a
  /// direct `has` lookup, since neither component is privileged in a
  /// two-component query and the smaller-first scan is strictly
  /// cheaper. For three or more components, chain a `.where(...)`
  /// using `hasComponent<C>` on the result.
  Iterable<EntityId> entitiesWithAll<A, B>() sync* {
    final storeA = _world.storeOf<A>();
    final storeB = _world.storeOf<B>();
    if (storeA.length <= storeB.length) {
      for (var i = 0; i < storeA.length; i++) {
        final id = storeA.entityAt(i);
        if (storeB.has(id)) yield id;
      }
    } else {
      for (var i = 0; i < storeB.length; i++) {
        final id = storeB.entityAt(i);
        if (storeA.has(id)) yield id;
      }
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

  /// All entities with a `Position` within [radius] of ([x], [y]) — for
  /// "what's near this point" queries (AI perception, an explosion's
  /// area of effect). Linear scan, same approach and the same caveat
  /// as [nearestWithPosition]: fine at the entity counts a single
  /// query needs; reach for `SpatialHash` directly in a System if you
  /// need this at scale across many simultaneous queriers per tick.
  /// Scoped to radius (a circle) rather than also offering a rect
  /// variant — circle covers every AoE/perception use case this engine
  /// has actually needed so far; add a rect query if a real one shows
  /// up rather than building it speculatively now.
  Iterable<EntityId> entitiesWithinRadius(
    double x,
    double y,
    double radius, {
    EntityId? exclude,
  }) sync* {
    final positions = _world.storeOf<Position>();
    final radiusSq = radius * radius;
    for (var i = 0; i < positions.length; i++) {
      final id = positions.entityAt(i);
      if (id == exclude) continue;
      final p = positions.denseAt(i);
      final dx = p.x - x;
      final dy = p.y - y;
      if (dx * dx + dy * dy <= radiusSq) yield id;
    }
  }

  /// Whether a straight line from ([fromX], [fromY]) to ([toX], [toY])
  /// is unobstructed by any solid tile in any `TileMap` in this world —
  /// built on `raycastTileMap`. The line-of-sight primitive AI
  /// `Behavior`s read directly (e.g. `FollowBehavior`'s
  /// `requireLineOfSight`) so "chasing" doesn't mean chasing through
  /// walls. [blockOneWay] matches `raycastTileMap`'s own default (off)
  /// — a one-way platform usually shouldn't block sight the way a real
  /// wall does.
  bool hasLineOfSight(
    double fromX,
    double fromY,
    double toX,
    double toY, {
    bool blockOneWay = false,
  }) {
    for (final mapEntity in entitiesWith<TileMap>()) {
      final map = component<TileMap>(mapEntity)!;
      final origin = component<Position>(mapEntity) ?? Position(0, 0);
      if (raycastTileMap(map, origin, fromX, fromY, toX, toY, blockOneWay: blockOneWay) != null) {
        return false;
      }
    }
    return true;
  }
}
