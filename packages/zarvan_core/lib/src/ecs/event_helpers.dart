import 'entity.dart';
import 'event_bus.dart';
import '../physics/collision_system.dart';
import 'world.dart';

/// Convenience wrappers over `world.events.on<CollisionEvent>` for the
/// pair-checking boilerplate every collision handler otherwise repeats
/// (`CollisionEvent.a`/`.b` are unordered, so "did X collide with Y"
/// always means checking both orderings by hand).
extension CollisionEventHelpers on World {
  /// Fires [callback] whenever [a] and [b] specifically collide with
  /// each other (order-independent).
  ///
  /// Stops by itself once either entity is destroyed, including when its id
  /// is later reused by a new entity (checked when the next collision event
  /// arrives). Returns the [Subscription] to cancel it sooner.
  Subscription onCollisionBetween(
    EntityId a,
    EntityId b,
    void Function() callback,
  ) {
    final genA = generationOf(a);
    final genB = generationOf(b);
    late final Subscription sub;
    sub = events.on<CollisionEvent>((e) {
      if (!entities.isCurrent(a, genA) || !entities.isCurrent(b, genB)) {
        sub.cancel();
        return;
      }
      if ((e.a == a && e.b == b) || (e.a == b && e.b == a)) callback();
    });
    return sub;
  }

  /// Fires [callback] whenever [entity] collides with anything, passing
  /// the *other* entity in the pair.
  ///
  /// Stops by itself once [entity] is destroyed, including when its id is
  /// later reused (checked when the next collision event arrives). Returns the
  /// [Subscription] to cancel it sooner.
  Subscription onCollisionInvolving(
    EntityId entity,
    void Function(EntityId other) callback,
  ) {
    final generation = generationOf(entity);
    late final Subscription sub;
    sub = events.on<CollisionEvent>((e) {
      if (!entities.isCurrent(entity, generation)) {
        sub.cancel();
        return;
      }
      if (e.a == entity) {
        callback(e.b);
      } else if (e.b == entity) {
        callback(e.a);
      }
    });
    return sub;
  }

  /// Fires [callback] whenever any entity in [group] collides with
  /// anything, passing the group member and the other entity.
  ///
  /// Unlike the single-entity helpers this does not stop on its own: [group]
  /// is a plain set of ids with no generations, so it cannot tell a dead
  /// member from a reused id. Cancel the returned [Subscription] when the
  /// group is done.
  Subscription onCollisionWithAny(
    Set<EntityId> group,
    void Function(EntityId self, EntityId other) callback,
  ) {
    return events.on<CollisionEvent>((e) {
      if (group.contains(e.a)) {
        callback(e.a, e.b);
      } else if (group.contains(e.b)) {
        callback(e.b, e.a);
      }
    });
  }
}
