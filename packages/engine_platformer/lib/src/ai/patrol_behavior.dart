import 'package:engine_core/engine_core.dart';

/// Walks back and forth between [minX] and [maxX] at [speed]. Direction
/// is persisted in the entity's own `AIState.memory['dir']` (1.0 or
/// -1.0) — a `Behavior` only ever sees a read-only `WorldView`, so
/// flipping direction has to happen through the returned `Action`'s
/// `apply(World)`, not inside `decide` itself.
///
/// [minX]/[maxX]/[speed] are this behavior's *defaults* — each is
/// overridden per-entity by an `AIState.memory['minX']`/`['maxX']`/
/// `['speed']` entry when present, so a level JSON can tune one
/// registered `behaviorId` (e.g. `'patrol'`) differently per enemy
/// entity via plain data, instead of a game having to register a
/// separate `PatrolBehavior` instance (and therefore a separate
/// `behaviorId`) per distinct range/speed combination it wants. A
/// level that sets no override in `memory` behaves exactly as if this
/// constructor's arguments were the only values, unchanged from
/// before this existed.
class PatrolBehavior implements Behavior {
  final double? minX;
  final double? maxX;
  final double speed;

  /// `false` (default, unchanged behavior): only [minX]/[maxX] bound
  /// direction, so an entity with no `Gravity`/`PlatformerController`
  /// (the common case for a simple ground patroller — see
  /// `spawnEnemy`'s doc comment) can walk straight out over a gap in
  /// the ground if its authored range reaches one, since nothing about
  /// this behavior ever looks at the level's actual tile geometry.
  /// `true` additionally checks, each tick, whether solid ground exists
  /// [ledgeCheckAheadDistance] ahead in the direction of travel — if
  /// not (a ledge/pit), flips direction *now* instead of only at the
  /// authored [minX]/[maxX] bound, so a range that was accidentally
  /// authored a little too wide (or a level edited later to add a new
  /// gap) can't walk an entity off the edge. Purely a safety net on top
  /// of [minX]/[maxX], not a replacement for them — a patroller still
  /// won't wander past its authored range even over solid ground.
  final bool avoidLedges;

  /// How far ahead (world px, in the current direction of travel) to
  /// probe for ground when [avoidLedges] is on. Meaningless otherwise.
  /// Should comfortably cover how far the entity can move in the worst
  /// realistic single tick (`speed * a slow frame's dt`) plus a margin,
  /// so the ledge is detected with room to actually turn before
  /// reaching it, not right as the last tick over solid ground ends.
  final double ledgeCheckAheadDistance;

  PatrolBehavior({
    this.minX,
    this.maxX,
    this.speed = 60,
    this.avoidLedges = false,
    this.ledgeCheckAheadDistance = 24,
  });

  @override
  Action decide(WorldView view, EntityId self) {
    final pos = view.component<Position>(self);
    final state = view.component<AIState>(self);
    if (pos == null || state == null) return const NoOpAction();

    final effectiveMinX = (state.memory['minX'] as num?)?.toDouble() ?? minX;
    final effectiveMaxX = (state.memory['maxX'] as num?)?.toDouble() ?? maxX;
    final effectiveSpeed = (state.memory['speed'] as num?)?.toDouble() ?? speed;
    if (effectiveMinX == null || effectiveMaxX == null) return const NoOpAction();

    final dir = (state.memory['dir'] as num?)?.toDouble() ?? 1.0;
    var shouldFlip =
        (dir > 0 && pos.x >= effectiveMaxX) || (dir < 0 && pos.x <= effectiveMinX);

    if (!shouldFlip && avoidLedges) {
      final aheadX = pos.x + dir * ledgeCheckAheadDistance;
      if (!_hasGroundBelow(view, self, aheadX, pos.y)) {
        shouldFlip = true;
      }
    }

    final newDir = shouldFlip ? -dir : dir;
    return _PatrolStepAction(self, newDir * effectiveSpeed, shouldFlip ? newDir : null);
  }

  /// Whether any `TileMap` in the world has a solid tile directly below
  /// ([x], [y]) — probed at the entity's own `Collider.radius` (or `12`
  /// if it has none) plus a small margin below [y], so this checks the
  /// ground actually under the entity's feet, not under its own center.
  bool _hasGroundBelow(WorldView view, EntityId self, double x, double y) {
    final radius = view.component<Collider>(self)?.radius ?? 12;
    final probeY = y + radius + 4;
    for (final mapEntity in view.entitiesWith<TileMap>()) {
      final map = view.component<TileMap>(mapEntity)!;
      final origin = view.component<Position>(mapEntity) ?? Position(0, 0);
      final col = ((x - origin.x) / map.tileWidth).floor();
      final row = ((probeY - origin.y) / map.tileHeight).floor();
      if (map.isSolid(col, row)) return true;
    }
    return false;
  }
}

class _PatrolStepAction implements Action {
  final EntityId entity;
  final double vx;

  /// Non-null only when the behavior decided to flip this tick — the
  /// new direction to persist into `AIState.memory` for next tick.
  final double? newDirection;

  _PatrolStepAction(this.entity, this.vx, this.newDirection);

  @override
  void apply(World world) {
    world.storeOf<Velocity>().set(entity, Velocity(vx, 0));
    final dir = newDirection;
    if (dir != null) {
      world.storeOf<AIState>().get(entity)?.memory['dir'] = dir;
    }
  }
}
