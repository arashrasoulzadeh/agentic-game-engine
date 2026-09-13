import 'package:engine_core/engine_core.dart';

import 'projectile.dart';

/// Ages every `Projectile` and destroys it once `elapsed` reaches
/// `lifetimeSeconds` — the passive half of projectile support (see
/// `installProjectileDamage` for the reactive, on-hit half). Harmless
/// in a world with no `Projectile` entities, so it's fine to always
/// register alongside other genre-general systems, the same as
/// `HealthSystem`.
class ProjectileSystem implements System {
  @override
  String get name => 'projectile';

  @override
  void update(World world, double dt) {
    final projectiles = world.storeOf<Projectile>();
    final expired = <EntityId>[];
    for (var i = 0; i < projectiles.length; i++) {
      final projectile = projectiles.denseAt(i);
      projectile.elapsed += dt;
      if (projectile.elapsed >= projectile.lifetimeSeconds) {
        expired.add(projectiles.entityAt(i));
      }
    }
    // Destroyed after the scan, not inline -- World.destroy triggers a
    // swap-remove in every component store, which would otherwise
    // shuffle indices out from under this loop mid-iteration (same
    // reasoning as ParticleSystem's _age).
    for (final id in expired) {
      world.destroy(id);
    }
  }
}
