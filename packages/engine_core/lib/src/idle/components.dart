import '../../engine_core.dart';

/// A bonus a generator earns for being owned in numbers: at [owned] copies its output is multiplied by
/// [multiplier] (the genre's "25 cursors: x2" ladder). Reached milestones stack.
class Milestone {
  /// Copies needed.
  final int owned;

  /// Factor applied to that generator's output once [owned] is reached.
  final BigNumber multiplier;

  const Milestone(this.owned, this.multiplier);

  Map<String, dynamic> toJson() => {
    'owned': owned,
    'multiplier': multiplier.toJson(),
  };

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
    (json['owned'] as num).toInt(),
    BigNumber.fromJson((json['multiplier'] ?? '2') as Object),
  );
}

/// Something the player buys copies of that produces resources every second: a cursor, a farm, a
/// factory. One entity per kind of generator; [owned] is how many the player has.
class Generator {
  /// Stable identifier that upgrades refer to (`"cursor"`).
  final String id;

  /// Display name; null shows [id].
  final String? name;

  /// How many the player owns.
  int owned;

  /// The most that can be owned; null for no limit.
  final int? maxOwned;

  /// The resource that pays for it.
  final String costResource;

  /// Price of the next copy as a function of [owned].
  final CostCurve cost;

  /// What **one** copy makes per second, by resource, before any bonus.
  final Map<String, BigNumber> output;

  /// Technologies the player needs before it can be bought (see `availableTech`).
  final List<String> requires;

  /// Output bonuses unlocked by owning many copies.
  final List<Milestone> milestones;

  Generator({
    required this.id,
    required this.cost,
    this.name,
    this.owned = 0,
    this.maxOwned,
    this.costResource = 'coins',
    Map<String, BigNumber>? output,
    List<String>? requires,
    List<Milestone>? milestones,
  }) : output = output ?? {},
       milestones = milestones ?? [],
       requires = requires ?? const [];

  /// The product of every milestone reached at the current [owned].
  BigNumber get milestoneMultiplier {
    var m = BigNumber.one;
    for (final ms in milestones) {
      if (owned >= ms.owned) m = m * ms.multiplier;
    }
    return m;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'owned': owned,
    if (maxOwned != null) 'maxOwned': maxOwned,
    'costResource': costResource,
    'cost': cost.toJson(),
    'output': {for (final e in output.entries) e.key: e.value.toJson()},
    if (requires.isNotEmpty) 'requires': requires,
    if (milestones.isNotEmpty)
      'milestones': [for (final m in milestones) m.toJson()],
  };

  factory Generator.fromJson(Map<String, dynamic> json) => Generator(
    id: json['id'] as String,
    name: json['name'] as String?,
    owned: (json['owned'] as num?)?.toInt() ?? 0,
    maxOwned: (json['maxOwned'] as num?)?.toInt(),
    costResource: json['costResource'] as String? ?? 'coins',
    cost: CostCurve.fromJson((json['cost'] as Map).cast<String, dynamic>()),
    output: {
      for (final e in ((json['output'] as Map?) ?? const {}).entries)
        e.key as String: BigNumber.fromJson(e.value as Object),
    },
    requires: [
      for (final r in (json['requires'] as List? ?? const [])) r as String,
    ],
    milestones: [
      for (final m in (json['milestones'] as List? ?? const []))
        Milestone.fromJson((m as Map).cast<String, dynamic>()),
    ],
  );
}

/// A one-off purchase that multiplies output once bought: "double all cursors".
class Upgrade {
  /// Stable identifier (also the name of its source in the modifier breakdown).
  final String id;

  /// Display name; null shows [id].
  final String? name;

  /// One-time price, by resource.
  final Map<String, BigNumber> cost;

  /// A [Generator.id] it applies to, or `all` for every generator.
  final String target;

  /// What it multiplies the target's output by.
  final BigNumber multiplier;

  /// Whether the player has bought it.
  bool purchased;

  /// Technologies needed before it can be bought.
  final List<String> requires;

  Upgrade({
    required this.id,
    required this.multiplier,
    this.name,
    Map<String, BigNumber>? cost,
    this.target = 'all',
    this.purchased = false,
    List<String>? requires,
  }) : cost = cost ?? {},
       requires = requires ?? const [];

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'cost': {for (final e in cost.entries) e.key: e.value.toJson()},
    'target': target,
    'multiplier': multiplier.toJson(),
    'purchased': purchased,
    if (requires.isNotEmpty) 'requires': requires,
  };

  factory Upgrade.fromJson(Map<String, dynamic> json) => Upgrade(
    id: json['id'] as String,
    name: json['name'] as String?,
    cost: {
      for (final e in ((json['cost'] as Map?) ?? const {}).entries)
        e.key as String: BigNumber.fromJson(e.value as Object),
    },
    target: json['target'] as String? ?? 'all',
    multiplier: BigNumber.fromJson((json['multiplier'] ?? '1') as Object),
    purchased: json['purchased'] as bool? ?? false,
    requires: [
      for (final r in (json['requires'] as List? ?? const [])) r as String,
    ],
  );
}

/// The game-wide bonuses (prestige, boosts, achievements) as named sources, applied to all income on
/// top of upgrades. One per game, on any entity.
class IdleModifiers {
  final ModifierStack stack;

  IdleModifiers([ModifierStack? stack]) : stack = stack ?? ModifierStack();

  Map<String, dynamic> toJson() => stack.toJson();
  factory IdleModifiers.fromJson(Map<String, dynamic> json) =>
      IdleModifiers(ModifierStack.fromJson(json));
}
