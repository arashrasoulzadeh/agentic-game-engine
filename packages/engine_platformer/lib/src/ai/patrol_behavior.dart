import 'package:engine_core/engine_core.dart';

/// Walks back and forth between [minX] and [maxX] at [speed]. Direction
/// is persisted in the entity's own `AIState.memory['dir']` (1.0 or
/// -1.0) — a `Behavior` only ever sees a read-only `WorldView`, so
/// flipping direction has to happen through the returned `Action`'s
/// `apply(World)`, not inside `decide` itself.
class PatrolBehavior implements Behavior {
  final double minX;
  final double maxX;
  final double speed;

  PatrolBehavior({required this.minX, required this.maxX, this.speed = 60});

  @override
  Action decide(WorldView view, EntityId self) {
    final pos = view.component<Position>(self);
    final state = view.component<AIState>(self);
    if (pos == null || state == null) return const NoOpAction();

    final dir = (state.memory['dir'] as num?)?.toDouble() ?? 1.0;
    final shouldFlip = (dir > 0 && pos.x >= maxX) || (dir < 0 && pos.x <= minX);
    final newDir = shouldFlip ? -dir : dir;
    return _PatrolStepAction(self, newDir * speed, shouldFlip ? newDir : null);
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
