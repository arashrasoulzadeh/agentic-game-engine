import 'entity.dart';
import '../physics/collision_system.dart';
import 'world.dart';

/// Convenience wrappers over `world.events.on<CollisionEvent>` for the
/// pair-checking boilerplate every collision handler otherwise repeats
/// (`CollisionEvent.a`/`.b` are unordered, so "did X collide with Y"
/// always means checking both orderings by hand).
extension CollisionEventHelpers on World {
  /// Fires [callback] whenever [a] and [b] specifically collide with
  /// each other (order-independent).
  void onCollisionBetween(EntityId a, EntityId b, void Function() callback) {
    events.on<CollisionEvent>((e) {
      if ((e.a == a && e.b == b) || (e.a == b && e.b == a)) callback();
    });
  }

  /// Fires [callback] whenever [entity] collides with anything, passing
  /// the *other* entity in the pair.
  void onCollisionInvolving(
    EntityId entity,
    void Function(EntityId other) callback,
  ) {
    events.on<CollisionEvent>((e) {
      if (e.a == entity) {
        callback(e.b);
      } else if (e.b == entity) {
        callback(e.a);
      }
    });
  }

  /// Fires [callback] whenever any member of [group] collides with
  /// something, passing (the group member, the other entity). Useful
  /// for "any coin touched by the player" style handlers without
  /// tracking each coin's own listener.
  void onCollisionWithAny(
    Set<EntityId> group,
    void Function(EntityId self, EntityId other) callback,
  ) {
    events.on<CollisionEvent>((e) {
      if (group.contains(e.a)) {
        callback(e.a, e.b);
      } else if (group.contains(e.b)) {
        callback(e.b, e.a);
      }
    });
  }
}
