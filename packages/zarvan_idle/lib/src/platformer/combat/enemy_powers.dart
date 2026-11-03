/// The passive powers of a fighter that the combat system acts on, parsed
/// from the effect text in its sidecar (`"powers": [{"effect": "..."}]` and
/// boss `"phases"`). Effects it does not recognise are ignored.
///
/// Recognised (case-insensitive):
/// - `+30% attack speed below 50% hp`, `+25% attack below 30% hp`, and a phase
///   `attack_speed x1.5` at `hp_below: 50` (rage)
/// - `25% chance to dodge each hero attack`
/// - `first strike each wave deals +50% damage`, `first attack deals 200% damage`
class EnemyPowers {
  EnemyPowers({
    this.rageBelowHp = 0,
    this.rageAttackSpeed = 1,
    this.rageAttack = 1,
    this.dodge = 0,
    this.firstStrike = 1,
    this.firstStrikeUsed = false,
  });

  /// Rage applies while health is at or below this fraction (0 = never).
  final double rageBelowHp;
  final double rageAttackSpeed;
  final double rageAttack;

  /// Chance (0..1) to avoid a hit entirely.
  final double dodge;

  /// Damage multiplier of the first attack only.
  final double firstStrike;
  bool firstStrikeUsed;

  bool get isEmpty => rageBelowHp == 0 && dodge == 0 && firstStrike == 1;

  /// Whether rage is active at [hpFraction] of max health.
  bool rageActive(double hpFraction) =>
      rageBelowHp > 0 && hpFraction <= rageBelowHp;

  /// Builds the powers from sidecar effect strings; null when none apply.
  static EnemyPowers? parse(Iterable<String> effects) {
    var rageHp = 0.0, rageSpeed = 1.0, rageAtk = 1.0, dodge = 0.0, first = 1.0;
    for (final raw in effects) {
      final e = raw.toLowerCase();
      var m = RegExp(
        r'\+(\d+(?:\.\d+)?)% attack speed below (\d+)% hp',
      ).firstMatch(e);
      if (m != null) {
        rageSpeed = 1 + double.parse(m[1]!) / 100;
        rageHp = double.parse(m[2]!) / 100;
        continue;
      }
      m = RegExp(r'\+(\d+(?:\.\d+)?)% attack below (\d+)% hp').firstMatch(e);
      if (m != null) {
        rageAtk = 1 + double.parse(m[1]!) / 100;
        rageHp = double.parse(m[2]!) / 100;
        continue;
      }
      m = RegExp(r'(\d+(?:\.\d+)?)% chance to dodge').firstMatch(e);
      if (m != null) {
        dodge = double.parse(m[1]!) / 100;
        continue;
      }
      m = RegExp(r'first strike.*\+(\d+(?:\.\d+)?)% damage').firstMatch(e);
      if (m != null) {
        first = 1 + double.parse(m[1]!) / 100;
        continue;
      }
      m = RegExp(r'first attack deals (\d+(?:\.\d+)?)% damage').firstMatch(e);
      if (m != null) {
        first = double.parse(m[1]!) / 100;
      }
    }
    final powers = EnemyPowers(
      rageBelowHp: rageHp,
      rageAttackSpeed: rageSpeed,
      rageAttack: rageAtk,
      dodge: dodge,
      firstStrike: first,
    );
    return powers.isEmpty ? null : powers;
  }

  Map<String, dynamic> toJson() => {
    'rageBelowHp': rageBelowHp,
    'rageAttackSpeed': rageAttackSpeed,
    'rageAttack': rageAttack,
    'dodge': dodge,
    'firstStrike': firstStrike,
    'firstStrikeUsed': firstStrikeUsed,
  };

  factory EnemyPowers.fromJson(Map<String, dynamic> json) => EnemyPowers(
    rageBelowHp: (json['rageBelowHp'] as num?)?.toDouble() ?? 0,
    rageAttackSpeed: (json['rageAttackSpeed'] as num?)?.toDouble() ?? 1,
    rageAttack: (json['rageAttack'] as num?)?.toDouble() ?? 1,
    dodge: (json['dodge'] as num?)?.toDouble() ?? 0,
    firstStrike: (json['firstStrike'] as num?)?.toDouble() ?? 1,
    firstStrikeUsed: json['firstStrikeUsed'] as bool? ?? false,
  );
}
