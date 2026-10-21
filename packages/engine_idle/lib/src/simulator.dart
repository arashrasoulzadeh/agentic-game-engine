import 'package:engine_core/engine_core.dart';

import 'components.dart';
import 'economy.dart';
import 'progression.dart';

/// One moment worth noting in a simulated game.
class SimulationMilestone {
  const SimulationMilestone(this.at, this.label);

  /// Simulated time since the start.
  final Duration at;
  final String label;
}

/// What a simulated play-through found.
class SimulationReport {
  SimulationReport(
    this.milestones,
    this.purchases,
    this.finalIncome,
    this.elapsed,
    this.stalled, [
    this.stallReason,
  ]);

  final List<SimulationMilestone> milestones;

  /// How many things the strategy bought.
  final int purchases;

  /// Income per second at the end, by resource.
  final Map<String, BigNumber> finalIncome;

  /// Simulated time covered.
  final Duration elapsed;

  /// Why it stalled, when [stalled] (for example `nothing left to buy` or `purchase refused: unaffordable`).
  final String? stallReason;

  /// True if the run ended because nothing more could ever be afforded (a dead end in the design), not
  /// because the time limit was reached.
  final bool stalled;
}

/// Plays [world] (already loaded, with its wallet) with a simple, deterministic strategy and reports when
/// it reaches milestones, so cost curves can be tuned without playing.
///
/// The strategy: always buy the single generator copy or upgrade with the best **payback** (cost divided by
/// the income it adds), waiting just long enough to afford it; prestige as soon as it would give at least
/// [prestigeAt] times what the player already holds (never, if there is no prestige rule or
/// [prestigeAt] is null). It is greedy and not optimal, but it is fair and repeatable: a design that
/// cannot progress under it is worth a second look.
///
/// Reports a milestone each time income of the main resource passes a power of ten, on each prestige, and
/// on each achievement.
SimulationReport simulateIdle(
  World world,
  BigTreasury wallet, {
  Duration limit = const Duration(days: 7),
  double? prestigeAt,
  String mainResource = 'coins',
  int maxActions = 5000,
}) {
  final milestones = <SimulationMilestone>[];
  var t = 0.0;
  var purchases = 0;
  var stalled = false;
  String? stallReason;
  var nextDecade = 0;

  recomputeIncome(world, wallet);
  final limitSeconds = limit.inSeconds.toDouble();

  void note(String label) =>
      milestones.add(SimulationMilestone(Duration(seconds: t.round()), label));

  void advance(double seconds) {
    if (seconds <= 0) return;
    wallet.accrue(seconds);
    final gains = {
      for (final e in wallet.incomePerSecond.entries)
        e.key: e.value * BigNumber.from(seconds),
    };
    final stats = world.storeOf<IdleStats>();
    if (stats.length > 0) {
      stats.denseAt(0)
        ..credit(gains)
        ..secondsPlayed += seconds;
    }
    t += seconds;
  }

  void checkMilestones() {
    final rate = wallet.rateOf(mainResource);
    if (rate > BigNumber.zero) {
      final decade = rate.log10().floor();
      while (nextDecade <= decade) {
        note('income reaches 1e$nextDecade $mainResource/s');
        nextDecade++;
      }
    }
    for (final id in checkAchievements(world, wallet)) {
      note('achievement: $id');
    }
  }

  for (var step = 0; step < maxActions && t < limitSeconds; step++) {
    checkMilestones();

    if (prestigeAt != null) {
      final gain = prestigeGainNow(world);
      final rules = world.storeOf<PrestigeRule>();
      if (rules.length > 0 && gain >= BigNumber.one) {
        final held = wallet.of(rules.denseAt(0).currency);
        if (held.isZero || gain >= held * BigNumber.from(prestigeAt)) {
          performPrestige(world, wallet);
          note(
            'prestige #${world.storeOf<IdleStats>().denseAt(0).prestigeCount} (+${gain.toString()})',
          );
          nextDecade = 0;
          continue;
        }
      }
    }

    // Candidates: one more copy of each generator, each unbought upgrade.
    _Option? best;
    // An option the player can never afford (nothing earns the resource it costs) is not a candidate.
    bool reachable(_Option o) =>
        o.cost <= wallet.of(o.resource) ||
        wallet.rateOf(o.resource) > BigNumber.zero;
    final before = computeIncome(world);
    final main = before[mainResource] ?? BigNumber.zero;

    final gens = world.storeOf<Generator>();
    for (var i = 0; i < gens.length; i++) {
      final id = gens.entityAt(i);
      final g = gens.denseAt(i);
      if (g.maxOwned != null && g.owned >= g.maxOwned!) continue;
      if (missingTech(world, 'player', g.requires).isNotEmpty) continue;
      g.owned++;
      final after =
          (computeIncome(world)[mainResource] ?? BigNumber.zero) - main;
      g.owned--;
      final cost = g.cost.costOfNext(g.owned);
      final option = _Option(id, false, g.costResource, cost, after);
      if (reachable(option)) best = _better(best, option);
    }
    final ups = world.storeOf<Upgrade>();
    for (var i = 0; i < ups.length; i++) {
      final id = ups.entityAt(i);
      final u = ups.denseAt(i);
      if (u.purchased || missingTech(world, 'player', u.requires).isNotEmpty) {
        continue;
      }
      u.purchased = true;
      final after =
          (computeIncome(world)[mainResource] ?? BigNumber.zero) - main;
      u.purchased = false;
      final cost = u.cost[mainResource] ?? BigNumber.zero;
      final option = _Option(id, true, mainResource, cost, after);
      if (reachable(option)) best = _better(best, option);
    }

    if (best == null || best.gain <= BigNumber.zero) {
      stalled = true;
      stallReason = 'nothing left to buy that adds income';
      break;
    }

    final rate = wallet.rateOf(best.resource);
    final missing = best.cost - wallet.of(best.resource);
    if (missing > BigNumber.zero) {
      if (rate <= BigNumber.zero) {
        stalled = true;
        stallReason = 'the next purchase costs a resource nothing earns';
        break;
      }
      // A hair over, so rounding in the accrual can never leave the wallet one ulp short.
      final wait = (missing / rate).toDouble() * (1 + 1e-9) + 1e-9;
      if (t + wait > limitSeconds) {
        advance(limitSeconds - t);
        break;
      }
      advance(wait);
    }
    final r = best.isUpgrade
        ? buyUpgrade(world, wallet, best.entity)
        : buyGenerator(world, wallet, best.entity);
    if (!r.ok) {
      stalled = true;
      stallReason = 'purchase refused: ${r.failure?.name}';
      break;
    }
    purchases++;
  }
  checkMilestones();
  return SimulationReport(
    milestones,
    purchases,
    computeIncome(world),
    Duration(seconds: t.round()),
    stalled,
    stallReason,
  );
}

class _Option {
  _Option(this.entity, this.isUpgrade, this.resource, this.cost, this.gain);
  final EntityId entity;
  final bool isUpgrade;
  final String resource;
  final BigNumber cost;
  final BigNumber gain;

  /// Cost per unit of income gained: lower is better.
  BigNumber get payback =>
      gain <= BigNumber.zero ? BigNumber.from(double.maxFinite) : cost / gain;
}

_Option? _better(_Option? current, _Option candidate) {
  if (candidate.gain <= BigNumber.zero) return current;
  if (current == null || candidate.payback < current.payback) return candidate;
  return current;
}
