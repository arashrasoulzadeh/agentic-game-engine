import '../../engine_core.dart';

import 'economy.dart';

/// A buyable research node: pays [cost], then [grantTech]s each id in [unlocks].
///
/// Generators / upgrades gate on those tech ids via their `requires` lists.
/// One entity per node; [purchased] is permanent for the run (survives prestige
/// unless you clear [TechState] yourself).
class ResearchNode {
  /// Stable id (also a useful default unlock name when [unlocks] is empty).
  final String id;

  /// Display name; null shows [id].
  final String? name;

  /// Optional [StringTable] key for [name].
  final String? nameKey;

  /// One-time price, by resource.
  final Map<String, BigNumber> cost;

  /// Tech ids that must already be available (see [missingTech]).
  final List<String> requires;

  /// Tech ids granted on purchase; defaults to `[id]` when omitted in JSON.
  final List<String> unlocks;

  /// Whether the player has bought it.
  bool purchased;

  ResearchNode({
    required this.id,
    this.name,
    this.nameKey,
    Map<String, BigNumber>? cost,
    List<String>? requires,
    List<String>? unlocks,
    this.purchased = false,
  }) : cost = cost ?? {},
       requires = requires ?? const [],
       unlocks = unlocks ?? [id];

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (nameKey != null) 'nameKey': nameKey,
    'cost': {for (final e in cost.entries) e.key: e.value.toJson()},
    if (requires.isNotEmpty) 'requires': requires,
    'unlocks': unlocks,
    'purchased': purchased,
  };

  factory ResearchNode.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return ResearchNode(
      id: id,
      name: json['name'] as String?,
      nameKey: json['nameKey'] as String?,
      cost: {
        for (final e in ((json['cost'] as Map?) ?? const {}).entries)
          e.key as String: BigNumber.fromJson(e.value as Object),
      },
      requires: [
        for (final r in (json['requires'] as List? ?? const [])) r as String,
      ],
      unlocks: json['unlocks'] == null
          ? [id]
          : [
              for (final u in (json['unlocks'] as List)) u as String,
            ],
      purchased: json['purchased'] as bool? ?? false,
    );
  }
}

/// Buys [research] once: spends [ResearchNode.cost], marks purchased, grants [unlocks].
BuyResult buyResearch(
  World world,
  BigTreasury wallet,
  EntityId research, {
  String team = 'player',
}) {
  final node = world.storeOf<ResearchNode>().get(research);
  if (node == null) return const BuyResult(0, {}, BuyFailure.nothing);
  if (node.purchased) return const BuyResult(0, {}, BuyFailure.alreadyBought);
  if (missingTech(world, team, node.requires).isNotEmpty) {
    return const BuyResult(0, {}, BuyFailure.locked);
  }
  if (!wallet.spend(node.cost)) {
    return const BuyResult(0, {}, BuyFailure.unaffordable);
  }
  node.purchased = true;
  for (final tech in node.unlocks) {
    grantTech(world, team, tech);
  }
  recomputeIncome(world, wallet);
  return BuyResult(1, Map.of(node.cost));
}
