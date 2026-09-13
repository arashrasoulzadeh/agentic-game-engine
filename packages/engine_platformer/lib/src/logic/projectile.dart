import 'package:engine_core/engine_core.dart';

/// Marks an entity as a projectile: something that moves in a straight
/// line (via the usual `Position`/`Velocity`/`MovementSystem` — nothing
/// projectile-specific about motion itself), expires after
/// [lifetimeSeconds] (`ProjectileSystem`), and deals [damage] to
/// whatever it hits other than [owner] (`installProjectileDamage`).
///
/// **Not handled**: colliding with solid level geometry (a wall, a
/// tile) — a projectile flies through walls unless a game adds its own
/// handling (e.g. a `PlatformerController` + gravity-free tile
/// collision check, or a custom system reading `TileMap` directly).
/// Most projectiles (arrows, bullets, fireballs) travel in a straight
/// line unaffected by gravity/platforming physics, so this deliberately
/// doesn't assume a `PlatformerController` the way `Pushable` recommends
/// pairing with one for wall-blocking.
class Projectile {
  double damage;
  double lifetimeSeconds;
  double elapsed;

  /// The entity that fired this projectile, if any — excluded from
  /// `installProjectileDamage`'s hit-detection so a projectile can't
  /// immediately damage its own shooter on spawn.
  EntityId? owner;

  Projectile({
    required this.damage,
    this.lifetimeSeconds = 3,
    this.elapsed = 0,
    this.owner,
  });

  Map<String, dynamic> toJson() => {
        'damage': damage,
        'lifetimeSeconds': lifetimeSeconds,
        'elapsed': elapsed,
        if (owner != null) 'owner': owner,
      };

  factory Projectile.fromJson(Map<String, dynamic> json) => Projectile(
        damage: (json['damage'] as num).toDouble(),
        lifetimeSeconds: (json['lifetimeSeconds'] as num?)?.toDouble() ?? 3,
        elapsed: (json['elapsed'] as num?)?.toDouble() ?? 0,
        owner: (json['owner'] as num?)?.toInt(),
      );
}
