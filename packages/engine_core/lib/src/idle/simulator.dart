import '../../engine_core.dart';

import 'advisor.dart';
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

    final best = bestPurchase(world, wallet, mainResource: mainResource);

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

String _duration(Duration d) {
  final days = d.inDays, h = d.inHours % 24, m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return [
    if (days > 0) '${days}d',
    if (days > 0 || h > 0) '${h}h',
    if (d.inHours < 24) '${m}m',
    if (d.inMinutes < 10) '${s}s',
  ].join(' ');
}

/// [report] as the plain text the command-line tools print: a summary line, one line per milestone and the
/// final income. One place for it so `game_agent idle simulate` and the package's own tool agree.
String describeSimulation(SimulationReport report) {
  final b = StringBuffer(
    'Simulated ${_duration(report.elapsed)}, ${report.purchases} purchases'
    '${report.stalled ? ' (stalled: ${report.stallReason})' : ''}.\n',
  );
  for (final m in report.milestones) {
    b.writeln('  ${_duration(m.at).padRight(10)} ${m.label}');
  }
  b.writeln('Final income:');
  for (final e in report.finalIncome.entries) {
    b.writeln('  ${formatBigNumber(e.value)} ${e.key}/s');
  }
  return b.toString();
}
