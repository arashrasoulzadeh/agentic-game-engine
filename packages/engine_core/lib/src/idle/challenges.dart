import '../../engine_core.dart';
import 'components.dart';
import 'economy.dart';
import 'progression.dart';

/// A restricted run with a goal and a permanent reward: "reach 1e6 coins with no upgrades".
///
/// Starting one restarts the run (like a prestige without the gain) with its [rules] in force; reaching the goal
/// ends the restriction and grants [reward] as a lasting income multiplier (modifier source `challenge:<id>`).
/// Rules: `noUpgrades`, `noGenerator:<generatorId>`, `incomeMultiplier:<factor>` (a handicap such as `0.1`).
class Challenge {
  final String id;
  final String? name;
  final List<String> rules;

  /// What is measured to finish (an achievement stat such as `run:coins`, see [achievementValue]).
  final String goalStat;
  final BigNumber goalAtLeast;

  /// Multiplier granted for good once completed (above 1).
  final BigNumber reward;

  bool active;
  bool completed;

  Challenge({
    required this.id,
    required this.goalStat,
    required this.goalAtLeast,
    this.name,
    this.rules = const [],
    BigNumber? reward,
    this.active = false,
    this.completed = false,
  }) : reward = reward ?? BigNumber.from(2);

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'rules': rules,
    'goalStat': goalStat,
    'goalAtLeast': goalAtLeast.toJson(),
    'reward': reward.toJson(),
    'active': active,
    'completed': completed,
  };

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
    id: json['id'] as String,
    name: json['name'] as String?,
    rules: [for (final r in (json['rules'] as List? ?? const [])) r as String],
    goalStat: json['goalStat'] as String,
    goalAtLeast: BigNumber.fromJson(json['goalAtLeast'] as Object),
    reward: BigNumber.fromJson((json['reward'] ?? '2') as Object),
    active: json['active'] as bool? ?? false,
    completed: json['completed'] as bool? ?? false,
  );
}

/// A challenge was just completed.
class ChallengeCompletedEvent {
  final String id;
  ChallengeCompletedEvent(this.id);
}

const _handicapSource = 'challenge';

/// The running challenge, or null.
Challenge? activeChallenge(World world) {
  final store = world.storeOf<Challenge>();
  for (var i = 0; i < store.length; i++) {
    if (store.denseAt(i).active) return store.denseAt(i);
  }
  return null;
}

/// Whether the running challenge forbids buying this thing: upgrades (`isUpgrade`) under `noUpgrades`, or the
/// generator [generatorId] under `noGenerator:<id>`.
bool challengeBlocks(
  World world, {
  required bool isUpgrade,
  String? generatorId,
}) {
  final c = activeChallenge(world);
  if (c == null) return false;
  for (final r in c.rules) {
    if (isUpgrade && r == 'noUpgrades') return true;
    if (!isUpgrade && r == 'noGenerator:$generatorId') return true;
  }
  return false;
}

BigNumber _handicap(Challenge c) {
  var f = BigNumber.one;
  for (final r in c.rules) {
    if (r.startsWith('incomeMultiplier:')) {
      final v = double.tryParse(r.substring('incomeMultiplier:'.length));
      if (v != null && v > 0) f = f * BigNumber.from(v);
    }
  }
  return f;
}

/// Starts challenge [id]: restarts the run (resources to the first prestige rule's starting amounts, generators
/// and upgrades reset, run earnings cleared except prestige currencies) and puts its rules in force. Returns
/// false if it does not exist, is already completed, or another challenge is running.
bool startChallenge(World world, BigTreasury wallet, String id) {
  final store = world.storeOf<Challenge>();
  Challenge? c;
  for (var i = 0; i < store.length; i++) {
    if (store.denseAt(i).id == id) c = store.denseAt(i);
  }
  if (c == null || c.completed || activeChallenge(world) != null) return false;

  final rule = prestigeRuleOf(world);
  final rules = world.storeOf<PrestigeRule>();
  final currencies = {
    for (var i = 0; i < rules.length; i++) rules.denseAt(i).currency,
  };
  final kept = {
    for (final cur in currencies)
      if (wallet.of(cur) > BigNumber.zero) cur: wallet.of(cur),
  };
  wallet.amounts
    ..clear()
    ..addAll(rule?.startingAmounts ?? const {})
    ..addAll(kept);
  final gens = world.storeOf<Generator>();
  for (var i = 0; i < gens.length; i++) {
    gens.denseAt(i).owned = 0;
  }
  final ups = world.storeOf<Upgrade>();
  for (var i = 0; i < ups.length; i++) {
    ups.denseAt(i).purchased = false;
  }
  final stats = world.storeOf<IdleStats>();
  if (stats.length > 0) {
    stats.denseAt(0).runEarned.removeWhere((r, _) => !currencies.contains(r));
  }
  c.active = true;
  final mods = world.storeOf<IdleModifiers>();
  if (mods.length > 0) {
    mods.denseAt(0).stack.setMultiplier(_handicapSource, _handicap(c));
  }
  recomputeIncome(world, wallet);
  return true;
}

/// Ends the running challenge without a reward (the run carries on unrestricted).
bool abandonChallenge(World world, BigTreasury wallet) {
  final c = activeChallenge(world);
  if (c == null) return false;
  c.active = false;
  final mods = world.storeOf<IdleModifiers>();
  if (mods.length > 0) mods.denseAt(0).stack.remove(_handicapSource);
  recomputeIncome(world, wallet);
  return true;
}

/// Completes the running challenge if its goal is met: lifts the restriction, grants the reward and emits a
/// [ChallengeCompletedEvent]. Returns its id, or null. `checkAchievements` calls it, so any code that checks
/// achievements after a purchase or a tick also settles challenges.
String? checkChallenges(World world, BigTreasury wallet) {
  final c = activeChallenge(world);
  if (c == null || achievementValue(world, c.goalStat) < c.goalAtLeast) {
    return null;
  }
  c.active = false;
  c.completed = true;
  final mods = world.storeOf<IdleModifiers>();
  if (mods.length > 0) {
    final stack = mods.denseAt(0).stack
      ..remove(_handicapSource)
      ..setMultiplier('challenge:${c.id}', c.reward);
    assert(stack.sources.contains('challenge:${c.id}'));
  }
  recomputeIncome(world, wallet);
  world.events.emit(ChallengeCompletedEvent(c.id));
  return c.id;
}
