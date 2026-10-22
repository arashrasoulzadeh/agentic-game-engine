import '../../engine_core.dart';
import 'advisor.dart';
import 'economy.dart';

/// Automation: every [intervalSeconds] it buys what has the best payback among the things the wallet can afford
/// (see [bestPurchase]), up to [maxPerRun] purchases. The genre's "auto-clicker / manager" tier: a game flips
/// [enabled] when the player unlocks it (for example from an upgrade's purchase), and an offline catch-up can
/// run it too (`IdleSession.whileAway`).
class AutoBuyer {
  bool enabled;

  /// Seconds between runs.
  final double intervalSeconds;

  /// The resource whose income the buyer maximises.
  final String mainResource;

  /// The most purchases in one run, so a huge wallet cannot buy thousands in a single tick.
  final int maxPerRun;

  /// Seconds accumulated towards the next run (saved, so a restore resumes mid-wait).
  double elapsed;

  AutoBuyer({
    this.enabled = true,
    this.intervalSeconds = 5,
    this.mainResource = 'coins',
    this.maxPerRun = 10,
    this.elapsed = 0,
  }) : assert(intervalSeconds > 0),
       assert(maxPerRun >= 1);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'intervalSeconds': intervalSeconds,
    'mainResource': mainResource,
    'maxPerRun': maxPerRun,
    'elapsed': elapsed,
  };

  factory AutoBuyer.fromJson(Map<String, dynamic> json) => AutoBuyer(
    enabled: json['enabled'] as bool? ?? true,
    intervalSeconds: (json['intervalSeconds'] as num?)?.toDouble() ?? 5,
    mainResource: json['mainResource'] as String? ?? 'coins',
    maxPerRun: (json['maxPerRun'] as num?)?.toInt() ?? 10,
    elapsed: (json['elapsed'] as num?)?.toDouble() ?? 0,
  );
}

/// Runs one purchase pass of [buyer] now and returns how many things were bought. Exposed so a catch-up
/// (`IdleSession.whileAway`) or a "buy now" button can use the same logic as the system.
int runAutoBuyer(World world, BigTreasury wallet, AutoBuyer buyer) {
  var bought = 0;
  while (bought < buyer.maxPerRun) {
    final option = bestPurchase(
      world,
      wallet,
      mainResource: buyer.mainResource,
      affordableOnly: true,
    );
    if (option == null) break;
    final result = option.isUpgrade
        ? buyUpgrade(world, wallet, option.entity)
        : buyGenerator(world, wallet, option.entity);
    if (!result.ok) break;
    bought++;
  }
  return bought;
}

/// Advances every enabled [AutoBuyer] and runs it when its interval is up. Add it after `IdleSystem`.
class AutoBuySystem extends System {
  @override
  String get name => 'auto-buy';

  @override
  void update(World world, double dt) {
    final buyers = world.storeOf<AutoBuyer>();
    final wallets = world.storeOf<BigTreasury>();
    if (buyers.length == 0 || wallets.length == 0 || dt <= 0) return;
    final wallet = wallets.denseAt(0);
    for (var i = 0; i < buyers.length; i++) {
      final b = buyers.denseAt(i);
      if (!b.enabled) continue;
      b.elapsed += dt;
      if (b.elapsed < b.intervalSeconds) continue;
      b.elapsed -= b.intervalSeconds;
      if (b.elapsed > b.intervalSeconds) b.elapsed = 0;
      runAutoBuyer(world, wallet, b);
    }
  }
}
