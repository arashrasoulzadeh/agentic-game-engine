/// A piece of equipment dropped by an enemy: one slot, one stat, one bonus.
class Gear {
  const Gear({
    required this.slot,
    required this.name,
    required this.stat,
    required this.bonus,
    this.rarity = GearRarity.common,
  });

  /// `weapon`, `armor` or `charm`: a hero wears one item per slot.
  final String slot;
  final String name;

  /// The fighter stat it raises (`attack`, `hp`, `armor`, `attack_speed`).
  final String stat;

  /// Fraction of the base stat added (0.12 = +12%).
  final double bonus;
  final GearRarity rarity;

  /// Whether this beats [other] in the same slot (a missing item always loses).
  bool betterThan(Gear? other) => other == null || bonus > other.bonus;

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'name': name,
    'stat': stat,
    'bonus': bonus,
    'rarity': rarity.name,
  };

  factory Gear.fromJson(Map<String, dynamic> json) => Gear(
    slot: json['slot'] as String,
    name: json['name'] as String,
    stat: json['stat'] as String,
    bonus: (json['bonus'] as num).toDouble(),
    rarity: GearRarity.values.firstWhere(
      (r) => r.name == json['rarity'],
      orElse: () => GearRarity.common,
    ),
  );
}

enum GearRarity { common, rare, epic }
