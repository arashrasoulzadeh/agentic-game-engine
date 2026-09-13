import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'combat_helpers.dart';
import 'components/projectile.dart';

/// Spawns a `Position`/`Velocity`/`Collider`/`Projectile` entity moving
/// at ([vx], [vy]) — the "shoot one" helper, matching `spawnPlayer`/
/// `spawnEnemy`'s "replaces the hand-spawned entity + component
/// boilerplate" role for combat instead of characters. Pass
/// [atlasId]/[spriteRegion] to also attach a `Sprite`. Actual movement
/// comes from `MovementSystem` (already registered by
/// `installPlatformerSystems`) — nothing projectile-specific about it.
EntityId spawnProjectile(
  World world, {
  required double x,
  required double y,
  required double vx,
  required double vy,
  required double damage,
  double radius = 4,
  double lifetimeSeconds = 3,
  EntityId? owner,
  String? atlasId,
  String? spriteRegion,
}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Velocity>().set(id, Velocity(vx, vy));
  world.storeOf<Collider>().set(id, Collider(radius));
  world.storeOf<Projectile>().set(
        id,
        Projectile(damage: damage, lifetimeSeconds: lifetimeSeconds, owner: owner),
      );
  if (atlasId != null && spriteRegion != null) {
    world.storeOf<Sprite>().set(id, Sprite(atlasId, spriteRegion));
  }
  return id;
}

/// Wires up projectile-vs-anything damage for the whole [world] in one
/// call — a `Projectile` that hits something with `Health` (other than
/// its own `owner`) deals its `damage` (via `damageEntity`, so
/// invincibility windows/death still apply normally) and is destroyed;
/// hitting anything without `Health` (another projectile, a
/// non-damageable prop) is a harmless pass-through.
///
/// One subscription for every projectile ever spawned, not one per
/// projectile — `EventBus` has no per-handler unsubscribe, so wiring
/// this per-instance (the way a one-off `onCollisionInvolving` call
/// does for something long-lived) would leak a handler for every
/// projectile fired over a play session. Call once, e.g. from
/// `Scene.populate`, after `CollisionSystem` is registered.
void installProjectileDamage(World world) {
  world.events.on<CollisionEvent>((event) {
    _handleHit(world, event.a, event.b);
    _handleHit(world, event.b, event.a);
  });
}

void _handleHit(World world, EntityId maybeProjectile, EntityId other) {
  final projectile = world.storeOf<Projectile>().get(maybeProjectile);
  if (projectile == null || other == projectile.owner) return;
  if (damageEntity(world, other, projectile.damage)) {
    world.destroy(maybeProjectile);
  }
}
