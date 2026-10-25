import '../../engine_core.dart';

import 'economy.dart';
import 'progression.dart';

/// A purchasable instant of income: spend [cost], then credit [seconds] of
/// current rates (no offline efficiency / cap — this is a paid skip, not AFK).
class TimeWarpOffer {
  final String id;
  final String? name;
  final String? nameKey;

  /// How many seconds of current income to grant.
  final int seconds;

  /// Price, by resource (often prestige gems).
  final Map<String, BigNumber> cost;

  TimeWarpOffer({
    required this.id,
    required this.seconds,
    this.name,
    this.nameKey,
    Map<String, BigNumber>? cost,
  }) : cost = cost ?? {};

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (nameKey != null) 'nameKey': nameKey,
    'seconds': seconds,
    'cost': {for (final e in cost.entries) e.key: e.value.toJson()},
  };

  factory TimeWarpOffer.fromJson(Map<String, dynamic> json) => TimeWarpOffer(
    id: json['id'] as String,
    name: json['name'] as String?,
    nameKey: json['nameKey'] as String?,
    seconds: (json['seconds'] as num).toInt(),
    cost: {
      for (final e in ((json['cost'] as Map?) ?? const {}).entries)
        e.key as String: BigNumber.fromJson(e.value as Object),
    },
  );
}

/// Credits [duration] of current [wallet] income rates and updates [IdleStats].
///
/// Returns what was gained (empty when [duration] is non-positive or income is zero).
Map<String, BigNumber> timeWarp(
  World world,
  BigTreasury wallet,
  Duration duration,
) {
  if (duration <= Duration.zero) return const {};
  recomputeIncome(world, wallet);
  final seconds = duration.inSeconds;
  if (seconds <= 0) return const {};
  final s = BigNumber.from(seconds);
  final gained = <String, BigNumber>{
    for (final e in wallet.incomePerSecond.entries)
      if (e.value > BigNumber.zero) e.key: e.value * s,
  };
  for (final e in gained.entries) {
    wallet.add(e.key, e.value);
  }
  final stats = world.storeOf<IdleStats>();
  if (stats.length > 0 && gained.isNotEmpty) {
    stats.denseAt(0).credit(gained);
  }
  return gained;
}

/// Spends [offer]'s cost then applies its [TimeWarpOffer.seconds] via [timeWarp].
BuyResult buyTimeWarp(
  World world,
  BigTreasury wallet,
  EntityId offer,
) {
  final o = world.storeOf<TimeWarpOffer>().get(offer);
  if (o == null) return const BuyResult(0, {}, BuyFailure.nothing);
  if (o.seconds <= 0) return const BuyResult(0, {}, BuyFailure.nothing);
  if (!wallet.spend(o.cost)) {
    return const BuyResult(0, {}, BuyFailure.unaffordable);
  }
  timeWarp(world, wallet, Duration(seconds: o.seconds));
  return BuyResult(1, Map.of(o.cost));
}
