/// `Weapon.kind`: whether an attack spawns a short-lived stationary
/// hitbox at melee range, or a moving projectile — see `AttackSystem`
/// for what each actually does.
enum WeaponKind { melee, ranged }

/// An entity's attack: what `AttackSystem` fires when its owner's
/// attack action is pressed and [isReady]. Both [WeaponKind]s reuse
/// `spawnProjectile`/`installProjectileDamage` under the hood (see
/// `AttackSystem`) rather than a separate hitbox mechanism — a melee
/// swing is just a projectile with zero velocity and a short
/// [meleeDurationSeconds] lifetime instead of [projectileLifetimeSeconds],
/// positioned [meleeRange] ahead of the attacker instead of moving
/// there itself.
class Weapon {
  WeaponKind kind;
  double damage;

  /// Minimum seconds between attacks — [AttackSystem] ignores the
  /// attack action while [cooldownRemaining] is still above `0`.
  double cooldownSeconds;

  /// Counts down to `0` every tick (`AttackSystem`); not meant to be
  /// set directly by game code, same as `Projectile.elapsed`.
  double cooldownRemaining;

  /// Set by `AttackSystem` reading the attack action, consumed the same
  /// tick — mirrors `PlatformerController.dashRequested`'s "request
  /// flag set by input, consumed by the system that acts on it" shape,
  /// so a game can also set this directly (e.g. from an AI behavior or
  /// a touch-screen attack button) without needing an `InputState`.
  bool attackRequested;

  /// [WeaponKind.melee] only: how far ahead of the attacker (in the
  /// direction it's facing) the hitbox is centered.
  double meleeRange;

  /// [WeaponKind.melee] only: the hitbox's `Collider` radius.
  double meleeRadius;

  /// [WeaponKind.melee] only: how long the hitbox stays active before
  /// disappearing (`Projectile.lifetimeSeconds` under the hood) — short
  /// enough to read as an instantaneous swing rather than a lingering
  /// hazard.
  double meleeDurationSeconds;

  /// [WeaponKind.ranged] only: the spawned projectile's speed, in the
  /// direction the attacker is facing.
  double projectileSpeed;

  /// [WeaponKind.ranged] only: the spawned projectile's `Collider`
  /// radius.
  double projectileRadius;

  /// [WeaponKind.ranged] only: how long the projectile travels before
  /// expiring (`Projectile.lifetimeSeconds`).
  double projectileLifetimeSeconds;

  /// [WeaponKind.ranged] only: forwarded to `spawnProjectile`'s
  /// `atlasId`/`spriteRegion` so a fired shot renders as a real sprite
  /// instead of nothing — `null` (the default) means no `Sprite` is
  /// attached, matching `spawnProjectile`'s own default.
  String? atlasId;
  String? spriteRegion;

  Weapon({
    this.kind = WeaponKind.melee,
    this.damage = 10,
    this.cooldownSeconds = 0.4,
    this.cooldownRemaining = 0,
    this.attackRequested = false,
    this.meleeRange = 24,
    this.meleeRadius = 12,
    this.meleeDurationSeconds = 0.12,
    this.projectileSpeed = 400,
    this.projectileRadius = 4,
    this.projectileLifetimeSeconds = 2,
    this.atlasId,
    this.spriteRegion,
  });

  bool get isReady => cooldownRemaining <= 0;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'damage': damage,
        'cooldownSeconds': cooldownSeconds,
        'cooldownRemaining': cooldownRemaining,
        'meleeRange': meleeRange,
        'meleeRadius': meleeRadius,
        'meleeDurationSeconds': meleeDurationSeconds,
        'projectileSpeed': projectileSpeed,
        'projectileRadius': projectileRadius,
        'projectileLifetimeSeconds': projectileLifetimeSeconds,
        if (atlasId != null) 'atlasId': atlasId,
        if (spriteRegion != null) 'spriteRegion': spriteRegion,
      };

  factory Weapon.fromJson(Map<String, dynamic> json) => Weapon(
        kind: WeaponKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => WeaponKind.melee,
        ),
        damage: (json['damage'] as num?)?.toDouble() ?? 10,
        cooldownSeconds: (json['cooldownSeconds'] as num?)?.toDouble() ?? 0.4,
        cooldownRemaining: (json['cooldownRemaining'] as num?)?.toDouble() ?? 0,
        meleeRange: (json['meleeRange'] as num?)?.toDouble() ?? 24,
        meleeRadius: (json['meleeRadius'] as num?)?.toDouble() ?? 12,
        meleeDurationSeconds: (json['meleeDurationSeconds'] as num?)?.toDouble() ?? 0.12,
        projectileSpeed: (json['projectileSpeed'] as num?)?.toDouble() ?? 400,
        projectileRadius: (json['projectileRadius'] as num?)?.toDouble() ?? 4,
        projectileLifetimeSeconds:
            (json['projectileLifetimeSeconds'] as num?)?.toDouble() ?? 2,
        atlasId: json['atlasId'] as String?,
        spriteRegion: json['spriteRegion'] as String?,
      );
}
