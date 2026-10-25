import '../../engine_core.dart';
import 'challenges.dart';
import 'components.dart';
import 'economy.dart';

/// Something the player could buy next, with what it would add.
class PurchaseOption {
  PurchaseOption(
    this.entity,
    this.isUpgrade,
    this.resource,
    this.cost,
    this.gain,
  );

  final EntityId entity;

  /// An upgrade (bought once) rather than one more copy of a generator.
  final bool isUpgrade;

  /// What it is paid with.
  final String resource;
  final BigNumber cost;

  /// Income per second it adds to the main resource.
  final BigNumber gain;

  /// Cost per unit of income gained: lower is better. Infinite-ish when it adds nothing.
  BigNumber get payback =>
      gain <= BigNumber.zero ? BigNumber.from(double.maxFinite) : cost / gain;
}

/// The purchase with the best **payback** (cost divided by the income it adds to [mainResource]), or null if
/// nothing adds income. One more copy of each generator and each unbought upgrade are considered, skipping
/// anything locked by technology or capped.
///
/// Upgrade cost uses [mainResource] when present on the upgrade, otherwise the first cost entry — so a
/// gem-only prestige-shop upgrade is never mistaken for a free coin buy.
///
/// With [affordableOnly] only options the wallet can pay for right now count (what an auto-buyer wants);
/// otherwise an option qualifies if it is affordable now or its resource is being earned (what the balance
/// simulator wants, since it will wait). It is greedy and not optimal, but it is deterministic, so a "recommended
/// buy" hint and an automation tier behave the same way every time.
PurchaseOption? bestPurchase(
  World world,
  BigTreasury wallet, {
  String mainResource = 'coins',
  String team = 'player',
  bool affordableOnly = false,
}) {
  bool eligible(PurchaseOption o) {
    final have = wallet.of(o.resource);
    if (o.cost <= have) return true;
    return !affordableOnly && wallet.rateOf(o.resource) > BigNumber.zero;
  }

  PurchaseOption? best;
  void consider(PurchaseOption o) {
    if (o.gain <= BigNumber.zero || !eligible(o)) return;
    if (best == null || o.payback < best!.payback) best = o;
  }

  final main = computeIncome(world)[mainResource] ?? BigNumber.zero;
  BigNumber gainOf() =>
      (computeIncome(world)[mainResource] ?? BigNumber.zero) - main;

  final gens = world.storeOf<Generator>();
  for (var i = 0; i < gens.length; i++) {
    final g = gens.denseAt(i);
    if (g.maxOwned != null && g.owned >= g.maxOwned!) continue;
    if (missingTech(world, team, g.requires).isNotEmpty) continue;
    if (challengeBlocks(world, isUpgrade: false, generatorId: g.id)) continue;
    g.owned++;
    final gain = gainOf();
    g.owned--;
    consider(
      PurchaseOption(
        gens.entityAt(i),
        false,
        g.costResource,
        g.cost.costOfNext(g.owned),
        gain,
      ),
    );
  }
  final ups = world.storeOf<Upgrade>();
  for (var i = 0; i < ups.length; i++) {
    final u = ups.denseAt(i);
    if (u.purchased ||
        missingTech(world, team, u.requires).isNotEmpty ||
        challengeBlocks(world, isUpgrade: true) ||
        u.cost.isEmpty) {
      continue;
    }
    // Prefer the main-resource price; otherwise the first cost entry (prestige-shop
    // gem upgrades must not look like a free coin buy when cost[main] is missing).
    final resource = u.cost.containsKey(mainResource)
        ? mainResource
        : u.cost.keys.first;
    final cost = u.cost[resource]!;
    u.purchased = true;
    final gain = gainOf();
    u.purchased = false;
    consider(
      PurchaseOption(ups.entityAt(i), true, resource, cost, gain),
    );
  }
  return best;
}
