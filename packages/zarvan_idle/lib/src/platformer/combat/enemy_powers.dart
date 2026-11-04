/// The passive powers of a fighter that the combat system acts on, parsed
/// from the effect text in its sidecar (`"powers": [{"effect": "..."}]` and
/// boss `"phases"`). Effects it does not recognise are ignored.
///
/// Recognised (case-insensitive):
/// - `+30% attack speed below 50% hp`, `+25% attack below 30% hp`, and a phase
///   `attack_speed x1.5` at `hp_below: 50` (rage)
/// - `25% chance to dodge each hero attack`
/// - `first strike each wave deals +50% damage`, `first attack deals 200% damage`
/// - `hits apply bleed: 2% hero max hp/s for 3s`, `hits poison: 2.5% hero max hp/s
///   for 4s, stacks x3`, `15% chance per hit to stun the hero 0.5s`
/// - `every 4th attack fires 3 arrows, each 60% damage`
class EnemyPowers {
  EnemyPowers({
    this.rageBelowHp = 0,
    this.rageAttackSpeed = 1,
    this.rageAttack = 1,
    this.dodge = 0,
    this.firstStrike = 1,
    this.firstStrikeUsed = false,
    this.bleedFraction = 0,
    this.bleedSeconds = 0,
    this.poisonFraction = 0,
    this.poisonSeconds = 0,
    this.poisonMaxStacks = 1,
    this.stunChance = 0,
    this.stunSeconds = 0,
    this.volleyEvery = 0,
    this.volleyArrows = 0,
    this.volleyDamage = 1,
    this.attacksMade = 0,
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

  /// Damage over time its hits put on the hero: fraction of the hero's max
  /// health per second, for how long (poison also stacks).
  final double bleedFraction, bleedSeconds;
  final double poisonFraction, poisonSeconds;
  final int poisonMaxStacks;

  /// Chance per hit to stun the hero, and for how long.
  final double stunChance, stunSeconds;

  /// Every [volleyEvery]th attack fires [volleyArrows] arrows each worth
  /// [volleyDamage] of an ordinary hit instead of one blow.
  final int volleyEvery, volleyArrows;
  final double volleyDamage;

  /// Attacks made so far, for the volley counter.
  int attacksMade;

  bool get isEmpty =>
      rageBelowHp == 0 &&
      dodge == 0 &&
      firstStrike == 1 &&
      bleedFraction == 0 &&
      poisonFraction == 0 &&
      stunChance == 0 &&
      volleyEvery == 0;

  /// Whether rage is active at [hpFraction] of max health.
  bool rageActive(double hpFraction) =>
      rageBelowHp > 0 && hpFraction <= rageBelowHp;

  /// Builds the powers from sidecar effect strings; null when none apply.
  static EnemyPowers? parse(Iterable<String> effects) {
    var rageHp = 0.0, rageSpeed = 1.0, rageAtk = 1.0, dodge = 0.0, first = 1.0;
    var bleedF = 0.0, bleedS = 0.0, poisonF = 0.0, poisonS = 0.0, stunC = 0.0;
    var stunS = 0.0, volleyN = 0, volleyArrows = 0, poisonStacks = 1;
    var volleyDmg = 1.0;
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
        continue;
      }
      m = RegExp(
        r'bleed: (\d+(?:\.\d+)?)%[^/]*/s for (\d+(?:\.\d+)?)s',
      ).firstMatch(e);
      if (m != null) {
        bleedF = double.parse(m[1]!) / 100;
        bleedS = double.parse(m[2]!);
        continue;
      }
      m = RegExp(
        r'poison: (\d+(?:\.\d+)?)%[^/]*/s for (\d+(?:\.\d+)?)s(?:, stacks x(\d+))?',
      ).firstMatch(e);
      if (m != null) {
        poisonF = double.parse(m[1]!) / 100;
        poisonS = double.parse(m[2]!);
        poisonStacks = int.tryParse(m[3] ?? '') ?? 1;
        continue;
      }
      m = RegExp(
        r'(\d+(?:\.\d+)?)% chance per hit to stun the hero (\d+(?:\.\d+)?)s',
      ).firstMatch(e);
      if (m != null) {
        stunC = double.parse(m[1]!) / 100;
        stunS = double.parse(m[2]!);
        continue;
      }
      m = RegExp(
        r'every (\d+)(?:st|nd|rd|th) attack fires (\d+) arrows, each (\d+(?:\.\d+)?)% damage',
      ).firstMatch(e);
      if (m != null) {
        volleyN = int.parse(m[1]!);
        volleyArrows = int.parse(m[2]!);
        volleyDmg = double.parse(m[3]!) / 100;
      }
    }
    final powers = EnemyPowers(
      rageBelowHp: rageHp,
      rageAttackSpeed: rageSpeed,
      rageAttack: rageAtk,
      dodge: dodge,
      firstStrike: first,
      bleedFraction: bleedF,
      bleedSeconds: bleedS,
      poisonFraction: poisonF,
      poisonSeconds: poisonS,
      poisonMaxStacks: poisonStacks,
      stunChance: stunC,
      stunSeconds: stunS,
      volleyEvery: volleyN,
      volleyArrows: volleyArrows,
      volleyDamage: volleyDmg,
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
    'bleedFraction': bleedFraction,
    'bleedSeconds': bleedSeconds,
    'poisonFraction': poisonFraction,
    'poisonSeconds': poisonSeconds,
    'poisonMaxStacks': poisonMaxStacks,
    'stunChance': stunChance,
    'stunSeconds': stunSeconds,
    'volleyEvery': volleyEvery,
    'volleyArrows': volleyArrows,
    'volleyDamage': volleyDamage,
    'attacksMade': attacksMade,
  };

  factory EnemyPowers.fromJson(Map<String, dynamic> json) => EnemyPowers(
    rageBelowHp: (json['rageBelowHp'] as num?)?.toDouble() ?? 0,
    rageAttackSpeed: (json['rageAttackSpeed'] as num?)?.toDouble() ?? 1,
    rageAttack: (json['rageAttack'] as num?)?.toDouble() ?? 1,
    dodge: (json['dodge'] as num?)?.toDouble() ?? 0,
    firstStrike: (json['firstStrike'] as num?)?.toDouble() ?? 1,
    firstStrikeUsed: json['firstStrikeUsed'] as bool? ?? false,
    bleedFraction: (json['bleedFraction'] as num?)?.toDouble() ?? 0,
    bleedSeconds: (json['bleedSeconds'] as num?)?.toDouble() ?? 0,
    poisonFraction: (json['poisonFraction'] as num?)?.toDouble() ?? 0,
    poisonSeconds: (json['poisonSeconds'] as num?)?.toDouble() ?? 0,
    poisonMaxStacks: (json['poisonMaxStacks'] as num?)?.toInt() ?? 1,
    stunChance: (json['stunChance'] as num?)?.toDouble() ?? 0,
    stunSeconds: (json['stunSeconds'] as num?)?.toDouble() ?? 0,
    volleyEvery: (json['volleyEvery'] as num?)?.toInt() ?? 0,
    volleyArrows: (json['volleyArrows'] as num?)?.toInt() ?? 0,
    volleyDamage: (json['volleyDamage'] as num?)?.toDouble() ?? 1,
    attacksMade: (json['attacksMade'] as num?)?.toInt() ?? 0,
  );
}
