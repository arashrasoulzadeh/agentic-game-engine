import '../../engine_core.dart';

import 'components.dart';
import 'economy.dart';
import 'progression.dart';

/// One reward step on a [SeasonPass]: unlocks when XP reaches [at].
class SeasonPassTier {
  /// XP threshold (same units as [SeasonPass.xpStat]).
  final BigNumber at;

  /// Resources granted on claim.
  final Map<String, BigNumber> grant;

  /// Optional permanent income multiplier (`seasonPass:<id>:<index>`).
  final BigNumber? multiplier;

  /// Optional tech id granted via [grantTech].
  final String? tech;

  const SeasonPassTier({
    required this.at,
    this.grant = const {},
    this.multiplier,
    this.tech,
  });

  Map<String, dynamic> toJson() => {
    'at': at.toJson(),
    if (grant.isNotEmpty)
      'grant': {for (final e in grant.entries) e.key: e.value.toJson()},
    if (multiplier != null) 'multiplier': multiplier!.toJson(),
    if (tech != null) 'tech': tech,
  };

  factory SeasonPassTier.fromJson(Map<String, dynamic> json) => SeasonPassTier(
    at: BigNumber.fromJson(json['at'] as Object),
    grant: {
      for (final e in ((json['grant'] as Map?) ?? const {}).entries)
        e.key as String: BigNumber.fromJson(e.value as Object),
    },
    multiplier: json['multiplier'] == null
        ? null
        : BigNumber.fromJson(json['multiplier'] as Object),
    tech: json['tech'] as String?,
  );
}

/// Battle-pass style track: XP from an achievement-style [xpStat], claim tiers in order.
///
/// One per game. [claimed] is how many leading tiers have been taken (0 = none).
class SeasonPass {
  final String id;
  final String? name;
  final String? nameKey;

  /// Same keys as achievements (`lifetime:coins`, `taps`, …) — see [achievementValue].
  final String xpStat;

  final List<SeasonPassTier> tiers;

  /// Number of tiers already claimed from the front of [tiers].
  int claimed;

  SeasonPass({
    required this.id,
    required this.xpStat,
    List<SeasonPassTier>? tiers,
    this.name,
    this.nameKey,
    this.claimed = 0,
  }) : tiers = tiers ?? const [];

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (nameKey != null) 'nameKey': nameKey,
    'xpStat': xpStat,
    'tiers': [for (final t in tiers) t.toJson()],
    'claimed': claimed,
  };

  factory SeasonPass.fromJson(Map<String, dynamic> json) => SeasonPass(
    id: json['id'] as String,
    name: json['name'] as String?,
    nameKey: json['nameKey'] as String?,
    xpStat: json['xpStat'] as String,
    tiers: [
      for (final t in (json['tiers'] as List? ?? const []))
        SeasonPassTier.fromJson((t as Map).cast<String, dynamic>()),
    ],
    claimed: (json['claimed'] as num?)?.toInt() ?? 0,
  );
}

/// Claims every newly earned tier on the world's [SeasonPass] (if any).
///
/// Returns how many tiers were claimed this call. Safe to call after purchases
/// (same cadence as [checkAchievements]).
int claimSeasonPass(
  World world,
  BigTreasury wallet, {
  String team = 'player',
}) {
  final store = world.storeOf<SeasonPass>();
  if (store.length == 0) return 0;
  final pass = store.denseAt(0);
  final xp = achievementValue(world, pass.xpStat);
  var n = 0;
  var modsChanged = false;
  while (pass.claimed < pass.tiers.length) {
    final tier = pass.tiers[pass.claimed];
    if (xp < tier.at) break;
    if (tier.grant.isNotEmpty) {
      for (final e in tier.grant.entries) {
        wallet.add(e.key, e.value);
      }
    }
    if (tier.multiplier != null && tier.multiplier! > BigNumber.one) {
      final mods = world.storeOf<IdleModifiers>();
      if (mods.length > 0) {
        mods.denseAt(0).stack.setMultiplier(
          'seasonPass:${pass.id}:${pass.claimed}',
          tier.multiplier!,
        );
        modsChanged = true;
      }
    }
    if (tier.tech != null && tier.tech!.isNotEmpty) {
      grantTech(world, team, tier.tech!);
    }
    pass.claimed++;
    n++;
  }
  if (modsChanged) recomputeIncome(world, wallet);
  return n;
}
