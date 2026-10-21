import 'package:engine_core/engine_core.dart';

import 'active_play.dart';
import 'progression.dart';

/// One thing a golden event can give: a timed income multiplier (`kind: "boost"`) or an instant payout of
/// [seconds] worth of current income (`kind: "payout"`).
class GoldenReward {
  /// `"boost"` or `"payout"`.
  final String kind;

  /// Income multiplier for a boost.
  final BigNumber multiplier;

  /// Boost duration, or seconds of income paid out.
  final double seconds;

  /// Relative likelihood against the other rewards.
  final double weight;

  GoldenReward({
    required this.kind,
    required this.seconds,
    BigNumber? multiplier,
    this.weight = 1,
  }) : multiplier = multiplier ?? BigNumber.one;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'multiplier': multiplier.toJson(),
    'seconds': seconds,
    'weight': weight,
  };

  factory GoldenReward.fromJson(Map<String, dynamic> json) => GoldenReward(
    kind: json['kind'] as String,
    multiplier: BigNumber.fromJson((json['multiplier'] ?? '1') as Object),
    seconds: (json['seconds'] as num).toDouble(),
    weight: (json['weight'] as num?)?.toDouble() ?? 1,
  );
}

/// The "golden cookie": every so often an offer appears for a short while; claiming it gives a random
/// reward. Data plus the state needed to resume mid-wait after a save.
class GoldenEvents {
  /// Average seconds between offers; the actual wait is uniform in 0.5x to 1.5x of this.
  final double meanInterval;

  /// How long an offer stays before it is missed.
  final double lifetime;

  final List<GoldenReward> rewards;

  /// Seconds until the next offer appears; negative means "not scheduled yet".
  double countdown;

  /// Index into [rewards] of the offer currently showing, or null.
  int? offered;

  /// Seconds left on the showing offer.
  double offerRemaining;

  GoldenEvents({
    required this.meanInterval,
    required this.lifetime,
    required this.rewards,
    this.countdown = -1,
    this.offered,
    this.offerRemaining = 0,
  });

  Map<String, dynamic> toJson() => {
    'meanInterval': meanInterval,
    'lifetime': lifetime,
    'rewards': [for (final r in rewards) r.toJson()],
    'countdown': countdown,
    if (offered != null) 'offered': offered,
    'offerRemaining': offerRemaining,
  };

  factory GoldenEvents.fromJson(Map<String, dynamic> json) => GoldenEvents(
    meanInterval: (json['meanInterval'] as num).toDouble(),
    lifetime: (json['lifetime'] as num).toDouble(),
    rewards: [
      for (final r in (json['rewards'] as List? ?? const []))
        GoldenReward.fromJson((r as Map).cast<String, dynamic>()),
    ],
    countdown: (json['countdown'] as num?)?.toDouble() ?? -1,
    offered: (json['offered'] as num?)?.toInt(),
    offerRemaining: (json['offerRemaining'] as num?)?.toDouble() ?? 0,
  );
}

/// A golden offer just appeared; the UI shows the clickable thing.
class GoldenOfferedEvent {
  /// Seconds the player has to claim it.
  final double lifetime;
  GoldenOfferedEvent(this.lifetime);
}

/// Spawns and expires golden offers, using the seeded [random] so a replay shows the same ones.
///
/// Add it after `IdleSystem`. It consumes randomness only when scheduling an offer or picking a reward,
/// never per tick, so the sequence depends on the game's events and not on the frame rate.
class GoldenEventSystem extends System {
  GoldenEventSystem(this.random);

  final DeterministicRandom random;

  @override
  String get name => 'golden-events';

  @override
  void update(World world, double dt) {
    final store = world.storeOf<GoldenEvents>();
    if (store.length == 0 || dt <= 0) return;
    final g = store.denseAt(0);
    if (g.rewards.isEmpty) return;

    if (g.offered != null) {
      g.offerRemaining -= dt;
      if (g.offerRemaining <= 0) {
        g.offered = null;
        _schedule(g);
      }
      return;
    }
    if (g.countdown < 0) _schedule(g);
    g.countdown -= dt;
    if (g.countdown <= 0) {
      g.offered = _pick(g);
      g.offerRemaining = g.lifetime;
      world.events.emit(GoldenOfferedEvent(g.lifetime));
    }
  }

  void _schedule(GoldenEvents g) => g.countdown = random.nextRange(
    g.meanInterval * 0.5,
    g.meanInterval * 1.5,
  );

  int _pick(GoldenEvents g) {
    final total = g.rewards.fold<double>(0, (a, r) => a + r.weight);
    var roll = random.nextDouble() * total;
    for (var i = 0; i < g.rewards.length; i++) {
      roll -= g.rewards[i].weight;
      if (roll < 0) return i;
    }
    return g.rewards.length - 1;
  }
}

/// Claims the showing golden offer, returning the reward given or null if none is showing. A boost
/// starts (replacing a running golden boost); a payout adds that many seconds of current income and
/// counts as earnings in the stats.
GoldenReward? claimGolden(World world, BigTreasury wallet) {
  final store = world.storeOf<GoldenEvents>();
  if (store.length == 0) return null;
  final g = store.denseAt(0);
  final index = g.offered;
  if (index == null) return null;
  final reward = g.rewards[index];
  g.offered = null;
  g.offerRemaining = 0;
  g.countdown = -1;

  if (reward.kind == 'boost') {
    activateBoost(
      world,
      wallet,
      id: 'golden',
      multiplier: reward.multiplier,
      seconds: reward.seconds,
    );
  } else {
    final seconds = BigNumber.from(reward.seconds);
    final gains = {
      for (final e in wallet.incomePerSecond.entries) e.key: e.value * seconds,
    };
    gains.forEach(wallet.add);
    final stats = world.storeOf<IdleStats>();
    if (stats.length > 0) stats.denseAt(0).credit(gains);
  }
  checkAchievements(world, wallet);
  return reward;
}
