import 'package:engine_core/engine_core.dart';

/// Chases [target] horizontally at [speed] — the "following" behavior
/// for a ground-based enemy/companion. Only ever touches `Velocity.x`
/// (via [_SetVelocityXAction], not the generic `SetVelocityAction`),
/// leaving `.y` alone so it doesn't fight gravity/jump every tick.
///
/// [maxDistance] (if set) is an aggro range: outside it, the entity
/// stops rather than chasing forever. [stopDistance] avoids jittering
/// back and forth once already alongside the target. [requireLineOfSight]
/// (off by default, so existing behavior is unchanged) makes it stop
/// chasing — same as being out of range — whenever `WorldView.hasLineOfSight`
/// says a wall is between it and [target], so "following" doesn't mean
/// chasing straight through solid geometry.
class FollowBehavior implements Behavior {
  final EntityId target;
  final double speed;
  final double? maxDistance;
  final double stopDistance;
  final bool requireLineOfSight;

  FollowBehavior({
    required this.target,
    this.speed = 80,
    this.maxDistance,
    this.stopDistance = 4,
    this.requireLineOfSight = false,
  });

  @override
  Action decide(WorldView view, EntityId self) {
    final pos = view.component<Position>(self);
    final targetPos = view.component<Position>(target);
    if (pos == null || targetPos == null) {
      return _SetVelocityXAction(self, 0);
    }

    final dx = targetPos.x - pos.x;
    final distance = dx.abs();
    final outOfRange = maxDistance != null && distance > maxDistance!;
    final blocked = requireLineOfSight &&
        !view.hasLineOfSight(pos.x, pos.y, targetPos.x, targetPos.y);
    if (outOfRange || blocked || distance <= stopDistance) {
      return _SetVelocityXAction(self, 0);
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
