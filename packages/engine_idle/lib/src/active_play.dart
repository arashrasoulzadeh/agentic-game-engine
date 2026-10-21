import 'package:engine_core/engine_core.dart';

import 'components.dart';
import 'economy.dart';
import 'progression.dart';

/// A temporary multiplier on all income ("x2 for 30 minutes"). While it runs it is the modifier source
/// `boost:<id>`; when [remaining] reaches zero [BoostSystem] removes it.
class Boost {
  final String id;
  final BigNumber multiplier;

  /// Seconds left.
  double remaining;

  Boost({required this.id, required this.multiplier, required this.remaining});

  Map<String, dynamic> toJson() => {
    'id': id,
    'multiplier': multiplier.toJson(),
    'remaining': remaining,
  };

  factory Boost.fromJson(Map<String, dynamic> json) => Boost(
    id: json['id'] as String,
    multiplier: BigNumber.fromJson(json['multiplier'] as Object),
    remaining: (json['remaining'] as num).toDouble(),
  );
}

/// Starts (or restarts, replacing the same [id]) a boost lasting [seconds], and refreshes income.
void activateBoost(
  World world,
  BigTreasury wallet, {
  required String id,
  required BigNumber multiplier,
  required double seconds,
}) {
  final boosts = world.storeOf<Boost>();
  Boost? existing;
  for (var i = 0; i < boosts.length; i++) {
    if (boosts.denseAt(i).id == id) existing = boosts.denseAt(i);
  }
  if (existing != null) {
    existing.remaining = seconds;
  } else {
    boosts.set(
      world.spawn(),
      Boost(id: id, multiplier: multiplier, remaining: seconds),
    );
  }
  final mods = world.storeOf<IdleModifiers>();
  if (mods.length > 0) {
    mods.denseAt(0).stack.setMultiplier('boost:$id', multiplier);
  }
  recomputeIncome(world, wallet);
}

/// Counts boosts down and ends the ones that run out, refreshing income when one does.
class BoostSystem extends System {
  @override
  String get name => 'boosts';

  @override
  void update(World world, double dt) {
    final boosts = world.storeOf<Boost>();
    if (boosts.length == 0) return;
    final ids = [for (var i = 0; i < boosts.length; i++) boosts.entityAt(i)]
      ..sort();
    var ended = false;
    for (final e in ids) {
      final b = boosts.get(e)!;
      b.remaining -= dt;
      if (b.remaining <= 0) {
        final mods = world.storeOf<IdleModifiers>();
        if (mods.length > 0) {
          mods.denseAt(0).stack.remove('boost:${b.id}');
        }
        world.destroy(e);
        ended = true;
      }
    }
    if (ended) {
      final wallets = world.storeOf<BigTreasury>();
      if (wallets.length > 0) {
        recomputeIncome(world, wallets.denseAt(0));
      }
    }
  }
}

/// A manual tap: earns [amount] of [resource] (default 1) times the game-wide multiplier, and records
/// the tap in [IdleStats]. Returns what was earned.
BigNumber tapEarn(
  World world,
  BigTreasury wallet, {
  String resource = 'coins',
  BigNumber? amount,
}) {
  final mods = world.storeOf<IdleModifiers>();
  final factor = mods.length == 0
      ? BigNumber.one
      : mods.denseAt(0).stack.totalMultiplier;
  final earned = (amount ?? BigNumber.one) * factor;
  wallet.add(resource, earned);
  final stats = world.storeOf<IdleStats>();
  if (stats.length > 0) {
    stats.denseAt(0).taps++;
    stats.denseAt(0).credit({resource: earned});
  }
  return earned;
}
