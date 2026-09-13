/// Hit points + a post-hit invincibility window, maintained by
/// `HealthSystem` (which only counts `invincibleSeconds` down each
/// tick) and mutated by `damageEntity`/`healEntity` (see
/// `combat_helpers.dart`) — nothing here applies damage itself, so a
/// game can attach `Health` to any entity without pulling in combat
/// behavior it doesn't want.
class Health {
  double current;
  double max;
  double invincibleSeconds;

  Health({required this.current, required this.max, this.invincibleSeconds = 0});

  bool get isDead => current <= 0;
  bool get isInvincible => invincibleSeconds > 0;

  Map<String, dynamic> toJson() => {
        'current': current,
        'max': max,
        'invincibleSeconds': invincibleSeconds,
      };

  factory Health.fromJson(Map<String, dynamic> json) => Health(
        current: (json['current'] as num).toDouble(),
        max: (json['max'] as num).toDouble(),
        invincibleSeconds: (json['invincibleSeconds'] as num?)?.toDouble() ?? 0,
      );
}
