/// What a [HeroSkill] does when used.
enum SkillKind {
  /// One heavy hit: attack times [HeroSkill.power] on the enemy.
  strike,

  /// Restores [HeroSkill.power] of the hero's max health.
  heal,

  /// For [HeroSkill.duration] seconds the hero takes [HeroSkill.power] less
  /// damage (0.6 = 60% less).
  guard,
}

/// An active ability on a button with a cooldown.
class HeroSkill {
  const HeroSkill({
    required this.id,
    required this.label,
    required this.kind,
    this.power = 2,
    this.cooldown = 12,
    this.duration = 4,
    this.icon,
  });

  final String id;
  final String label;
  final SkillKind kind;

  /// Frame index in the icon strip (`WaveUiArt.iconsStem`) drawn on the
  /// button, or null for a text-only button.
  final int? icon;

  /// Strike: damage multiplier. Heal: fraction of max hp. Guard: damage cut.
  final double power;

  /// Seconds before it can be used again.
  final double cooldown;

  /// Seconds a guard lasts (ignored by the others).
  final double duration;
}

/// Cooldown bookkeeping for a set of [HeroSkill]s, advanced by real time.
class SkillCooldowns {
  SkillCooldowns(this.skills);

  final List<HeroSkill> skills;
  final Map<String, double> _remaining = {};

  /// Seconds until [skill] is ready (0 when ready).
  double remaining(HeroSkill skill) => _remaining[skill.id] ?? 0;

  bool ready(HeroSkill skill) => remaining(skill) <= 0;

  /// Starts [skill]'s cooldown; false if it was not ready.
  bool use(HeroSkill skill) {
    if (!ready(skill)) return false;
    _remaining[skill.id] = skill.cooldown;
    return true;
  }

  void tick(double dt) {
    for (final id in _remaining.keys.toList()) {
      final left = _remaining[id]! - dt;
      if (left <= 0) {
        _remaining.remove(id);
      } else {
        _remaining[id] = left;
      }
    }
  }
}
