import 'package:engine_core/engine_core.dart';

/// Sets an entity's horizontal velocity, preserving whatever vertical
/// velocity is already there.
///
/// Every AI `Behavior`'s `Action` in this package (`FollowBehavior`,
/// `PatrolBehavior`, `PathFollowBehavior`, `InvestigateBehavior`) only
/// ever decides a horizontal move — none of them own gravity or jump
/// arcs — but each independently read `Velocity.y` back out and re-set
/// it unchanged, or (once, in `PatrolBehavior`) hardcoded it to `0` by
/// mistake. That mistake silently broke falling for any gravity-affected
/// patroller, since `AISystem` runs after `GravitySystem`/
/// `MovementSystem` in the documented system order, so an action that
/// drops the existing `vy` discards whatever vertical speed gravity had
/// already accumulated that tick. Centralizing the "preserve vy" rule
/// here means a future horizontal-only behavior can't repeat that
/// mistake by copy-pasting one of the few call sites that got it wrong.
void setVelocityX(World world, EntityId entity, double vx) {
  final store = world.storeOf<Velocity>();
  final existing = store.get(entity);
  store.set(entity, Velocity(vx, existing?.y ?? 0));
}
