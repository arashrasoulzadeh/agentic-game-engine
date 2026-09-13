import 'collider.dart';
import 'position.dart';
import 'pushable.dart';
import 'velocity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';

/// Sets a `Pushable` entity's `Velocity.x` from whether something solid
/// is currently overlapping it horizontally — see `Pushable`'s doc
/// comment for the "no wall-blocking here, pair with
/// `PlatformerController` for that" design. Any other `Collider`
/// entity can push (not just the player), matching how a pushed crate
/// doesn't care whether it's the player or an enemy shoving it.
///
/// Only counts a pusher roughly at the same height (within the
/// pushable's own radius vertically) as actually pushing — otherwise a
/// player jumping over a crate, or one resting on a much taller stack,
/// would "push" it purely from an overlap that isn't really a
/// horizontal shove. Pushed from both sides at once cancels out to no
/// movement, the same as a real object squeezed between two pushers.
///
/// Harmless (a no-op loop) in a world with no `Pushable` entities, so
/// it's fine to always register alongside other genre-general systems.
class PushableSystem implements System {
  @override
  String get name => 'pushable';

  @override
  void update(World world, double dt) {
    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();
    final colliders = world.storeOf<Collider>();
    final pushables = world.storeOf<Pushable>();

    for (var i = 0; i < pushables.length; i++) {
      final entity = pushables.entityAt(i);
      final pushable = pushables.denseAt(i);
      final pos = positions.get(entity);
      final vel = velocities.get(entity);
      final collider = colliders.get(entity);
      if (pos == null || vel == null || collider == null) continue;

      var pushDirection = 0;
      for (var j = 0; j < colliders.length; j++) {
        final other = colliders.entityAt(j);
        if (other == entity) continue;
        final otherPos = positions.get(other);
        if (otherPos == null) continue;
        final otherCollider = colliders.denseAt(j);

        final dx = pos.x - otherPos.x;
        final dy = pos.y - otherPos.y;
        if (dy.abs() > collider.radius) continue; // not roughly level

        final minDist = collider.radius + otherCollider.radius;
        if (dx == 0 || dx.abs() >= minDist) continue; // not overlapping horizontally

        pushDirection += dx > 0 ? 1 : -1;
      }

      vel.x = pushDirection == 0 ? 0 : pushable.pushSpeed * (pushDirection > 0 ? 1 : -1);
    }
  }
}
