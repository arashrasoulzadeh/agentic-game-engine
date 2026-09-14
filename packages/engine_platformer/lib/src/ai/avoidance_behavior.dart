import 'package:engine_core/engine_core.dart';

/// Wraps another `Behavior` and blends in a horizontal separation push
/// away from nearby AI-controlled entities — the "packs of enemies
/// overlap/stack" gap `PatrolBehavior`/`FollowBehavior`/
/// `PathFollowBehavior` all share, since none of them are aware of any
/// entity but themselves (and, for `FollowBehavior`, its single
/// `target`).
///
/// Deliberately a decorator around an existing `Behavior` rather than
/// logic bolted onto each one — the three behaviors it wraps would
/// otherwise all need the same nearby-entity scan and push-apart math
/// duplicated three times (and drifting out of sync the moment one of
/// them changed). Wrap any of them (or a custom `Behavior`) the same
/// way: `AvoidanceBehavior(PatrolBehavior(...))`.
///
/// Only pushes away from other entities that also carry `AIState` —
/// not literally everything within [avoidRadius] (the player, a coin,
/// a projectile) — so this reads as "keep this pack of AI entities
/// spread out," not "avoid all physical contact with anything." Purely
/// horizontal (`Velocity.x`), matching every behavior it wraps, which
/// all leave `.y` to gravity/jump.
///
/// Applies [inner]'s own `Action` first, unmodified, then adds the
/// separation push on top — [inner] still fully owns its own decision
/// (patrol range, follow target, path progress); this only ever nudges
/// the resulting `Velocity.x`, never overrides it outright, so two
/// entities pushed apart don't fight over who's "really" in control.
class AvoidanceBehavior implements Behavior {
  final Behavior inner;

  /// How close another AI-controlled entity has to be before this one
  /// starts steering away from it.
  final double avoidRadius;

  /// Push speed (px/s) applied at zero distance, falling off linearly
  /// to `0` at [avoidRadius] — the same "stronger push when closer"
  /// shape a physical separation force has, without needing real
  /// physics for something this cheap to fake.
  final double avoidStrength;

  AvoidanceBehavior(this.inner, {this.avoidRadius = 40, this.avoidStrength = 80});

  @override
  Action decide(WorldView view, EntityId self) {
    final innerAction = inner.decide(view, self);
    final pos = view.component<Position>(self);
    if (pos == null) return innerAction;

    var pushX = 0.0;
    for (final other in view.entitiesWithinRadius(pos.x, pos.y, avoidRadius, exclude: self)) {
      if (view.component<AIState>(other) == null) continue;
      final otherPos = view.component<Position>(other);
      if (otherPos == null) continue;

      final dx = pos.x - otherPos.x;
      final distance = dx.abs();
      // Exactly overlapping (distance 0): no defined push direction --
      // pick a stable one (push right) rather than dividing by zero or
      // leaving both entities stuck exactly on top of each other with
      // zero net force.
      final direction = distance < 0.001 ? 1.0 : dx.sign;
      final strength = avoidStrength * (1 - (distance / avoidRadius).clamp(0.0, 1.0));
      pushX += direction * strength;
    }

    if (pushX == 0) return innerAction;
    return _AvoidancePushAction(inner: innerAction, entity: self, pushX: pushX);
  }
}

class _AvoidancePushAction implements Action {
  final Action inner;
  final EntityId entity;
  final double pushX;

  _AvoidancePushAction({required this.inner, required this.entity, required this.pushX});

  @override
  void apply(World world) {
    inner.apply(world);
    final vel = world.storeOf<Velocity>().get(entity);
    if (vel != null) vel.x += pushX;
  }
}
