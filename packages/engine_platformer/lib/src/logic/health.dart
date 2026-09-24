/// Hit points + a post-hit invincibility window, maintained by
/// `HealthSystem` (which only counts `invincibleSeconds` down each
/// tick) and mutated by `damageEntity`/`healEntity` (see
/// `combat_helpers.dart`) — nothing here applies damage itself, so a
/// game can attach `Health` to any entity without pulling in combat
/// behavior it doesn't want.
///
/// Extended with guard/block and poise/stability system:
/// - When [isGuarding] is true, incoming damage is reduced by [guardDamageReduction]
///   (default 1.0 = fully blocked) and [stability] is depleted instead of health.
/// - When [stability] reaches 0, guard breaks ([isGuardBroken] becomes true),
///   the entity is stunned for [guardBreakStunSeconds], and takes full damage.
/// - [stability] recovers at [stabilityRegenPerSecond] when not guarding and not broken.
class Health {
  double current;
  double max;
  double invincibleSeconds;

  /// Whether the entity is currently guarding/blocking.
  /// Set/cleared by game code (e.g., input system or AI behavior).
  bool isGuarding;

  /// Damage reduction while guarding (0.0 = no reduction, 1.0 = full block).
  /// Defaults to 1.0 (completely block damage while guarding).
  double guardDamageReduction;

  /// Current stability/poise meter. Depletes when blocking hits.
  /// When reaches 0, guard breaks.
  double stability;

  /// Maximum stability/poise. Defaults to [max] if not set.
  double maxStability;

  /// Seconds until guard recovers after being broken.
  /// During this time, [isGuardBroken] is true and entity cannot guard.
  double guardBreakStunSeconds;

  /// Timer counting down guard break stun. Managed by HealthSystem.
  double guardBreakTimer;

  /// Stability regenerated per second when not guarding and not guard broken.
  double stabilityRegenPerSecond;

  Health({
    required this.current,
    required this.max,
    this.invincibleSeconds = 0,
    this.isGuarding = false,
    this.guardDamageReduction = 1.0,
    this.stability = 0,
    this.maxStability = 0,
    this.guardBreakStunSeconds = 1.0,
    this.guardBreakTimer = 0,
    this.stabilityRegenPerSecond = 10,
  });

  bool get isDead => current <= 0;
  bool get isInvincible => invincibleSeconds > 0;

  /// Whether the guard is currently broken (stunned from guard break).
  bool get isGuardBroken => guardBreakTimer > 0;

  /// Effective max stability (defaults to max health if not explicitly set).
  double get effectiveMaxStability => maxStability > 0 ? maxStability : max;

  /// Whether the entity can currently guard (not dead, not invincible, not guard broken).
  bool get canGuard => !isDead && !isInvincible && !isGuardBroken && effectiveMaxStability > 0;

  /// Current stability as a fraction of max (0.0 to 1.0).
  double get stabilityFraction => effectiveMaxStability > 0 ? (stability / effectiveMaxStability).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'current': current,
        'max': max,
        'invincibleSeconds': invincibleSeconds,
        'isGuarding': isGuarding,
        'guardDamageReduction': guardDamageReduction,
        'stability': stability,
        'maxStability': maxStability,
        'guardBreakStunSeconds': guardBreakStunSeconds,
        'guardBreakTimer': guardBreakTimer,
        'stabilityRegenPerSecond': stabilityRegenPerSecond,
      };

  factory Health.fromJson(Map<String, dynamic> json) => Health(
        current: (json['current'] as num).toDouble(),
        max: (json['max'] as num).toDouble(),
        invincibleSeconds: (json['invincibleSeconds'] as num?)?.toDouble() ?? 0,
        isGuarding: (json['isGuarding'] as bool?) ?? false,
        guardDamageReduction: (json['guardDamageReduction'] as num?)?.toDouble() ?? 1.0,
        stability: (json['stability'] as num?)?.toDouble() ?? 0,
        maxStability: (json['maxStability'] as num?)?.toDouble() ?? 0,
        guardBreakStunSeconds: (json['guardBreakStunSeconds'] as num?)?.toDouble() ?? 1.0,
        guardBreakTimer: (json['guardBreakTimer'] as num?)?.toDouble() ?? 0,
        stabilityRegenPerSecond: (json['stabilityRegenPerSecond'] as num?)?.toDouble() ?? 10,
      );
}