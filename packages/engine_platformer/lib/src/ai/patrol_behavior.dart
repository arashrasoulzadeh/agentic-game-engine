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

  PatrolBehavior({this.minX, this.maxX, this.speed = 60});

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
    final shouldFlip =
        (dir > 0 && pos.x >= effectiveMaxX) || (dir < 0 && pos.x <= effectiveMinX);
    final newDir = shouldFlip ? -dir : dir;
    return _PatrolStepAction(self, newDir * effectiveSpeed, shouldFlip ? newDir : null);
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
