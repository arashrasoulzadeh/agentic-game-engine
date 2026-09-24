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
///
/// Supports multi-hit melee combo chains via [comboCount], [comboWindowSeconds],
/// and per-step overrides in [comboSteps]. When [comboCount] > 1 and the weapon
/// is [WeaponKind.melee], pressing attack again within [comboWindowSeconds] of
/// the previous hit landing advances to the next combo step (up to [comboCount]).
/// Missing the window or a whiff (hitbox not connecting) resets the combo to step 0.
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

  /// Number of hits in the melee combo chain. Only used for [WeaponKind.melee].
  /// Defaults to 1 (no combo). When > 1, pressing attack within [comboWindowSeconds]
  /// after a hit lands advances to the next step.
  int comboCount;

  /// Time window (seconds) after a hit lands during which the next attack input
  /// is buffered to continue the combo. If the window expires, the combo resets.
  double comboWindowSeconds;

  /// Timer counting down the combo window. Managed by [AttackSystem].
  double comboTimer;

  /// Current step in the combo (0 = first hit, 1 = second hit, etc.).
  /// Managed by [AttackSystem]; 0 means no active combo or ready for first hit.
  int currentComboStep;

  /// Optional per-step damage multipliers. If provided, must have length
  /// equal to [comboCount]. Defaults to 1.0 for all steps if null.
  List<double>? comboDamageMultipliers;

  /// Optional per-step cooldown overrides (seconds). If provided, must have
  /// length equal to [comboCount]. Defaults to [cooldownSeconds] for all steps if null.
  List<double>? comboCooldowns;

  /// Optional per-step melee range overrides. If provided, must have
  /// length equal to [comboCount]. Defaults to [meleeRange] for all steps if null.
  List<double>? comboMeleeRanges;

  /// Optional per-step melee radius overrides. If provided, must have
  /// length equal to [comboCount]. Defaults to [meleeRadius] for all steps if null.
  List<double>? comboMeleeRadii;

  /// Optional per-step melee duration overrides. If provided, must have
  /// length equal to [comboCount]. Defaults to [meleeDurationSeconds] for all steps if null.
  List<double>? comboMeleeDurations;

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
    this.comboCount = 1,
    this.comboWindowSeconds = 0.5,
    this.comboTimer = 0,
    this.currentComboStep = 0,
    this.comboDamageMultipliers,
    this.comboCooldowns,
    this.comboMeleeRanges,
    this.comboMeleeRadii,
    this.comboMeleeDurations,
  });

  bool get isReady => cooldownRemaining <= 0;

  /// Returns the damage for the current combo step.
  double get currentDamage {
    if (comboDamageMultipliers != null && currentComboStep < comboDamageMultipliers!.length) {
      return damage * comboDamageMultipliers![currentComboStep];
    }
    return damage;
  }

  /// Returns the cooldown for the current combo step.
  double get currentCooldown {
    if (comboCooldowns != null && currentComboStep < comboCooldowns!.length) {
      return comboCooldowns![currentComboStep];
    }
    return cooldownSeconds;
  }

  /// Returns the melee range for the current combo step.
  double get currentMeleeRange {
    if (comboMeleeRanges != null && currentComboStep < comboMeleeRanges!.length) {
      return comboMeleeRanges![currentComboStep];
    }
    return meleeRange;
  }

  /// Returns the melee radius for the current combo step.
  double get currentMeleeRadius {
    if (comboMeleeRadii != null && currentComboStep < comboMeleeRadii!.length) {
      return comboMeleeRadii![currentComboStep];
    }
    return meleeRadius;
  }

  /// Returns the melee duration for the current combo step.
  double get currentMeleeDuration {
    if (comboMeleeDurations != null && currentComboStep < comboMeleeDurations!.length) {
      return comboMeleeDurations![currentComboStep];
    }
    return meleeDurationSeconds;
  }

  /// Resets combo state to initial values.
  void resetCombo() {
    currentComboStep = 0;
    comboTimer = 0;
  }

  /// Advances to the next combo step, or resets if at the end.
  void advanceCombo() {
    if (currentComboStep + 1 < comboCount) {
      currentComboStep++;
    } else {
      resetCombo();
    }
  }

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
        'comboCount': comboCount,
        'comboWindowSeconds': comboWindowSeconds,
        'comboTimer': comboTimer,
        'currentComboStep': currentComboStep,
        if (comboDamageMultipliers != null) 'comboDamageMultipliers': comboDamageMultipliers,
        if (comboCooldowns != null) 'comboCooldowns': comboCooldowns,
        if (comboMeleeRanges != null) 'comboMeleeRanges': comboMeleeRanges,
        if (comboMeleeRadii != null) 'comboMeleeRadii': comboMeleeRadii,
        if (comboMeleeDurations != null) 'comboMeleeDurations': comboMeleeDurations,
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
        comboCount: (json['comboCount'] as int?) ?? 1,
        comboWindowSeconds: (json['comboWindowSeconds'] as num?)?.toDouble() ?? 0.5,
        comboTimer: (json['comboTimer'] as num?)?.toDouble() ?? 0,
        currentComboStep: (json['currentComboStep'] as int?) ?? 0,
        comboDamageMultipliers: (json['comboDamageMultipliers'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        comboCooldowns: (json['comboCooldowns'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        comboMeleeRanges: (json['comboMeleeRanges'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        comboMeleeRadii: (json['comboMeleeRadii'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        comboMeleeDurations: (json['comboMeleeDurations'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        atlasId: json['atlasId'] as String?,
        spriteRegion: json['spriteRegion'] as String?,
      );
}