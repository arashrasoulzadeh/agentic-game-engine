import '../../engine_core.dart';

import 'challenges.dart';
import 'components.dart';
import 'progression.dart';

/// Everything per second a game's generators make right now, by resource: for each generator,
/// `owned * output`, multiplied by every purchased upgrade that targets it (or `all`) and by the
/// game-wide [IdleModifiers]. Synergy upgrades (`Upgrade.bonusPerOwned`) scale with how many of
/// [Upgrade.synergyOf] are owned.
Map<String, BigNumber> computeIncome(World world) {
  final generators = world.storeOf<Generator>();
  final upgrades = world.storeOf<Upgrade>();
  final global = _globalMultiplier(world);

  final ownedById = <String, int>{
    for (var i = 0; i < generators.length; i++)
      generators.denseAt(i).id: generators.denseAt(i).owned,
  };

  final bought = [
    for (var i = 0; i < upgrades.length; i++)
      if (upgrades.denseAt(i).purchased) upgrades.denseAt(i),
  ];

  final income = <String, BigNumber>{};
  for (final id in _sortedIds(generators.length, generators.entityAt)) {
    final g = generators.get(id)!;
    if (g.owned <= 0) continue;
    var factor = global * BigNumber.from(g.owned) * g.milestoneMultiplier;
    for (final u in bought) {
      if (u.target != 'all' && u.target != g.id) continue;
      factor = factor * u.multiplier;
      final bonus = u.bonusPerOwned;
      final syn = u.synergyOf;
      if (bonus != null && syn != null) {
        factor =
            factor *
            (BigNumber.one + bonus * BigNumber.from(ownedById[syn] ?? 0));
      }
    }
    for (final e in g.output.entries) {
      income[e.key] = (income[e.key] ?? BigNumber.zero) + e.value * factor;
    }
  }
  return income;
}

/// Writes [computeIncome] into [wallet]'s income rates. Call it after anything that changes income -
/// a purchase, a prestige, a boost starting or ending - not every tick: the rates are data the
/// treasury then accrues cheaply.
void recomputeIncome(World world, BigTreasury wallet) {
  wallet.incomePerSecond
    ..clear()
    ..addAll(computeIncome(world));
}

BigNumber _globalMultiplier(World world) {
  final mods = world.storeOf<IdleModifiers>();
  var m = BigNumber.one;
  for (var i = 0; i < mods.length; i++) {
    m = m * mods.denseAt(i).stack.totalMultiplier;
  }
  return m;
}

List<int> _sortedIds(int length, int Function(int) entityAt) =>
    [for (var i = 0; i < length; i++) entityAt(i)]..sort();

/// Why a purchase did or did not happen.
enum BuyFailure {
  unaffordable,
  locked,
  maxOwned,
  alreadyBought,
  nothing,

  /// The running challenge forbids it.
  challenge,
}

/// The outcome of a purchase.
class BuyResult {
  const BuyResult(this.bought, this.spent, [this.failure]);

  /// How many units were bought (0 or 1 for an upgrade).
  final int bought;

  /// What it cost, by resource.
  final Map<String, BigNumber> spent;

  /// Set when nothing was bought.
  final BuyFailure? failure;

  bool get ok => bought > 0;
}

/// Buys up to [count] of [generator] with [wallet]'s money, or as many as affordable with
/// [count] = null ("max"). All or nothing per unit count: it never spends a partial price. Updates the
/// wallet's income rates on success.
///
/// [team] is whose technologies unlock it (see `availableTech`).
BuyResult buyGenerator(
  World world,
  BigTreasury wallet,
  EntityId generator, {
  int? count = 1,
  String team = 'player',
}) {
  final g = world.storeOf<Generator>().get(generator);
  if (g == null) return const BuyResult(0, {}, BuyFailure.nothing);
  if (missingTech(world, team, g.requires).isNotEmpty) {
    return const BuyResult(0, {}, BuyFailure.locked);
  }
  if (challengeBlocks(world, isUpgrade: false, generatorId: g.id)) {
    return const BuyResult(0, {}, BuyFailure.challenge);
  }
  final room = g.maxOwned == null ? (1 << 30) : g.maxOwned! - g.owned;
  if (room <= 0) return const BuyResult(0, {}, BuyFailure.maxOwned);

  final want = count == null
      ? g.cost.maxAffordable(g.owned, wallet.of(g.costResource), limit: room)
      : count.clamp(0, room);
  if (want <= 0) return const BuyResult(0, {}, BuyFailure.unaffordable);

  final price = g.cost.totalCost(g.owned, want);
  if (!wallet.spend({g.costResource: price})) {
    return const BuyResult(0, {}, BuyFailure.unaffordable);
  }
  g.owned += want;
  recomputeIncome(world, wallet);
  return BuyResult(want, {g.costResource: price});
}

/// Buys [upgrade] once. Updates the wallet's income rates on success.
BuyResult buyUpgrade(
  World world,
  BigTreasury wallet,
  EntityId upgrade, {
  String team = 'player',
}) {
  final u = world.storeOf<Upgrade>().get(upgrade);
  if (u == null) return const BuyResult(0, {}, BuyFailure.nothing);
  if (u.purchased) return const BuyResult(0, {}, BuyFailure.alreadyBought);
  if (challengeBlocks(world, isUpgrade: true)) {
    return const BuyResult(0, {}, BuyFailure.challenge);
  }
  if (missingTech(world, team, u.requires).isNotEmpty) {
    return const BuyResult(0, {}, BuyFailure.locked);
  }
  if (!wallet.spend(u.cost)) {
    return const BuyResult(0, {}, BuyFailure.unaffordable);
  }
  u.purchased = true;
  recomputeIncome(world, wallet);
  return BuyResult(1, Map.of(u.cost));
}

/// Advances every [BigTreasury]'s resources by `dt`. Add it to a world that runs live; offline catch-up
/// uses `OfflineProgress` instead.
class IdleSystem extends System {
  @override
  String get name => 'idle';

  @override
  void update(World world, double dt) {
    final wallets = world.storeOf<BigTreasury>();
    final stats = world.storeOf<IdleStats>();
    final track = stats.length == 0 ? null : stats.denseAt(0);
    for (var i = 0; i < wallets.length; i++) {
      final w = wallets.denseAt(i);
      w.accrue(dt);
      if (track != null && dt > 0) {
        final seconds = BigNumber.from(dt);
        track.credit({
          for (final e in w.incomePerSecond.entries) e.key: e.value * seconds,
        });
      }
    }
    if (track != null) track.secondsPlayed += dt;
  }
}
