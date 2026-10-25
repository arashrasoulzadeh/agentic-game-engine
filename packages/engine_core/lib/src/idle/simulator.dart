import '../../engine_core.dart';

import 'advisor.dart';
import 'challenges.dart';
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
/// the income it adds), waiting just long enough to afford it; prestige as soon as any layer would give at
/// least [prestigeAt] times what the player already holds of that layer's currency (never, if there is no
/// prestige rule or [prestigeAt] is null) — higher layers first so an ascension that is ready is not skipped
/// while cheaper first-layer prestiges keep firing; skip prestige while a challenge is running (a prestige
/// would wipe the challenge's run stats). When [playChallenges] is true (the default), start each incomplete
/// challenge in definition order as soon as none is active, play under its restrictions until the goal is
/// met, then move on — so a definition's challenges are exercised, not ignored.
///
/// Reports a milestone each time income of the main resource passes a power of ten, on each prestige, on
/// each challenge start/completion, and on each achievement.
SimulationReport simulateIdle(
  World world,
  BigTreasury wallet, {
  Duration limit = const Duration(days: 7),
  double? prestigeAt,
  bool playChallenges = true,
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
    final challengeId = checkChallenges(world, wallet);
    if (challengeId != null) note('challenge completed: $challengeId');
    for (final id in checkAchievements(world, wallet)) {
      note('achievement: $id');
    }
  }

  /// Starts the next incomplete challenge; returns true when one began (the run was reset).
  bool tryStartNextChallenge() {
    if (!playChallenges || activeChallenge(world) != null) return false;
    final store = world.storeOf<Challenge>();
    for (var i = 0; i < store.length; i++) {
      final c = store.denseAt(i);
      if (c.completed) continue;
      if (!startChallenge(world, wallet, c.id)) continue;
      note('challenge start: ${c.id}');
      nextDecade = 0;
      return true;
    }
    return false;
  }

  /// Prestiges the highest-index layer that meets [prestigeAt]; returns true when one fired.
  bool tryPrestige() {
    if (prestigeAt == null || activeChallenge(world) != null) return false;
    final rules = world.storeOf<PrestigeRule>();
    // Highest layer first: otherwise a ready ascension waits forever behind repeated first-layer prestiges.
    for (var i = rules.length - 1; i >= 0; i--) {
      final rule = rules.denseAt(i);
      final gain = prestigeGainNow(world, rule.id);
      if (gain < BigNumber.one) continue;
      final held = wallet.of(rule.currency);
      if (held.isZero || gain >= held * BigNumber.from(prestigeAt)) {
        performPrestige(world, wallet, rule.id);
        final label = rule.id == 'prestige' ? 'prestige' : 'prestige ${rule.id}';
        note(
          '$label #${world.storeOf<IdleStats>().denseAt(0).prestigeCount} (+${gain.toString()})',
        );
        nextDecade = 0;
        return true;
      }
    }
    return false;
  }

  for (var step = 0; step < maxActions && t < limitSeconds; step++) {
    checkMilestones();

    if (tryPrestige()) continue;

    if (tryStartNextChallenge()) continue;

    final best = bestPurchase(world, wallet, mainResource: mainResource);

    if (best == null || best.gain <= BigNumber.zero) {
      // A challenge start resets the run; try that before calling the design a dead end.
      if (tryStartNextChallenge()) continue;
      stalled = true;
      stallReason = 'nothing left to buy that adds income';
      break;
    }

    final rate = wallet.rateOf(best.resource);
    final missing = best.cost - wallet.of(best.resource);
    if (missing > BigNumber.zero) {
      if (rate <= BigNumber.zero) {
        if (tryStartNextChallenge()) continue;
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
