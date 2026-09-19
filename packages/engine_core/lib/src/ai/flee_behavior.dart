import 'package:engine_core/engine_core.dart';

/// Flees from [target] at [speed] — the opposite of [FollowBehavior].
/// Only touches `Velocity.x` (via [_SetVelocityXAction]), leaving `.y`
/// alone so it doesn't fight gravity/jump every tick.
///
/// [minDistance] (if set) stops fleeing once the entity is at least this
/// far from the target — useful so an enemy doesn't run infinitely.
/// [stopDistance] avoids jittering back and forth once already far enough.
/// [requireLineOfSight] (off by default) makes it stop fleeing — same as
/// being within [minDistance] — whenever a wall blocks line of sight to
/// the target, so "fleeing" doesn't mean running straight through solid
/// geometry.
class FleeBehavior implements Behavior {
  final EntityId target;
  final double speed;
  final double? minDistance;
  final double stopDistance;
  final bool requireLineOfSight;

  FleeBehavior({
    required this.target,
    this.speed = 80,
    this.minDistance,
    this.stopDistance = 4,
    this.requireLineOfSight = false,
  });

  @override
  Action decide(WorldView view, EntityId self) {
    final pos = view.component<Position>(self);
    final targetPos = view.component<Position>(target);
    if (pos == null || targetPos == null) {
      return const NoOpAction();
    }

    final dx = pos.x - targetPos.x;
    final distance = dx.abs();
    final blocked = requireLineOfSight &&
        !view.hasLineOfSight(pos.x, pos.y, targetPos.x, targetPos.y);

    if (blocked) {
      return _SetVelocityXAction(self, 0);
    }

    if (minDistance != null) {
      final stopBoundary = minDistance! - stopDistance;
      if (distance >= stopBoundary) {
        return _SetVelocityXAction(self, 0);
      }
    }

    return _SetVelocityXAction(self, dx.sign * speed);
  }
}

class _SetVelocityXAction implements Action {
  final EntityId entity;
  final double vx;

  _SetVelocityXAction(this.entity, this.vx);

  @override
  void apply(World world) {
    final store = world.storeOf<Velocity>();
    final existing = store.get(entity);
    store.set(entity, Velocity(vx, existing?.y ?? 0));
  }
}