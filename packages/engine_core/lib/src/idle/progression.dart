import '../../engine_core.dart';

import 'components.dart';
import 'economy.dart';

/// Lifetime numbers the genre's rules are built on: prestige formulas, achievements and "stats"
/// screens. One per game, on any entity.
class IdleStats {
  /// Everything earned in the **current run** (since the last prestige), by resource.
  final Map<String, BigNumber> runEarned;

  /// Everything ever earned, across prestiges.
  final Map<String, BigNumber> lifetimeEarned;

  /// How many times the player has prestiged.
  int prestigeCount;

  /// Manual taps/clicks.
  int taps;

  /// Seconds of play time (live ticks only; offline time does not count).
  double secondsPlayed;

  IdleStats({
    Map<String, BigNumber>? runEarned,
    Map<String, BigNumber>? lifetimeEarned,
    this.prestigeCount = 0,
    this.taps = 0,
    this.secondsPlayed = 0,
  }) : runEarned = runEarned ?? {},
       lifetimeEarned = lifetimeEarned ?? {};

  /// Records [gains] (resource -> amount), e.g. an offline catch-up's `OfflineSummary.gained`.
  void credit(Map<String, BigNumber> gains) {
    for (final e in gains.entries) {
      runEarned[e.key] = (runEarned[e.key] ?? BigNumber.zero) + e.value;
      lifetimeEarned[e.key] =
          (lifetimeEarned[e.key] ?? BigNumber.zero) + e.value;
    }
  }

  Map<String, dynamic> toJson() => {
    'runEarned': {for (final e in runEarned.entries) e.key: e.value.toJson()},
    'lifetimeEarned': {
      for (final e in lifetimeEarned.entries) e.key: e.value.toJson(),
    },
    'prestigeCount': prestigeCount,
    'taps': taps,
    'secondsPlayed': secondsPlayed,
  };

  factory IdleStats.fromJson(Map<String, dynamic> json) {
    Map<String, BigNumber> read(String k) => {
      for (final e in ((json[k] as Map?) ?? const {}).entries)
        e.key as String: BigNumber.fromJson(e.value as Object),
    };
    return IdleStats(
      runEarned: read('runEarned'),
      lifetimeEarned: read('lifetimeEarned'),
      prestigeCount: (json['prestigeCount'] as num?)?.toInt() ?? 0,
      taps: (json['taps'] as num?)?.toInt() ?? 0,
      secondsPlayed: (json['secondsPlayed'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// How prestige works in a game, as data.
///
/// On prestige the player gives up their run (resources, generators, upgrades) and gains
/// `floor((runEarned / divisor) ^ exponent)` of [currency]. That currency is kept forever and each unit
/// adds [bonusPerUnit] to a game-wide multiplier (`1 + bonusPerUnit * held`).
class PrestigeRule {
  /// The permanent currency (`"gems"`). It is never reset.
  final String currency;

  /// The resource whose run total decides the gain.
  final String basedOn;

  /// Run earnings per unit at exponent 1; larger means prestige pays less.
  final BigNumber divisor;

  /// Shapes the curve: `0.5` is a square root (the classic), `1` is linear.
  final double exponent;

  /// Added to the multiplier per unit of [currency] held (`0.1` is +10% each).
  final double bonusPerUnit;

  /// What the player restarts with after prestige, by resource.
  final Map<String, BigNumber> startingAmounts;

  /// Keep purchased upgrades across prestige.
  final bool keepUpgrades;

  PrestigeRule({
    required this.currency,
    required this.basedOn,
    required this.divisor,
    this.exponent = 0.5,
    this.bonusPerUnit = 0.1,
    Map<String, BigNumber>? startingAmounts,
    this.keepUpgrades = false,
  }) : startingAmounts = startingAmounts ?? {};

  /// What prestiging would give for [earnedThisRun]. Zero until the run is worth at least one unit.
  BigNumber gainFor(BigNumber earnedThisRun) {
    if (earnedThisRun <= BigNumber.zero) return BigNumber.zero;
    return (earnedThisRun / divisor).pow(exponent).floor();
  }

  Map<String, dynamic> toJson() => {
    'currency': currency,
    'basedOn': basedOn,
    'divisor': divisor.toJson(),
    'exponent': exponent,
    'bonusPerUnit': bonusPerUnit,
    'startingAmounts': {
      for (final e in startingAmounts.entries) e.key: e.value.toJson(),
    },
    'keepUpgrades': keepUpgrades,
  };

  factory PrestigeRule.fromJson(Map<String, dynamic> json) => PrestigeRule(
    currency: json['currency'] as String,
    basedOn: json['basedOn'] as String,
    divisor: BigNumber.fromJson((json['divisor'] ?? '1') as Object),
    exponent: (json['exponent'] as num?)?.toDouble() ?? 0.5,
    bonusPerUnit: (json['bonusPerUnit'] as num?)?.toDouble() ?? 0.1,
    startingAmounts: {
      for (final e in ((json['startingAmounts'] as Map?) ?? const {}).entries)
        e.key as String: BigNumber.fromJson(e.value as Object),
    },
    keepUpgrades: json['keepUpgrades'] as bool? ?? false,
  );
}

/// Name of the modifier source prestige writes into [IdleModifiers].
const prestigeSource = 'prestige';

/// What prestiging right now would give, from the game's [IdleStats] and [PrestigeRule].
BigNumber prestigeGainNow(World world) {
  final rule = _first<PrestigeRule>(world);
  final stats = _first<IdleStats>(world);
  if (rule == null || stats == null) return BigNumber.zero;
  return rule.gainFor(stats.runEarned[rule.basedOn] ?? BigNumber.zero);
}

/// Resets the run and banks the prestige currency. Returns the amount gained, or null if the run is
/// not yet worth a unit (nothing changes then).
///
/// Resets: every resource except the permanent currency (back to [PrestigeRule.startingAmounts]),
/// every generator's `owned`, and - unless [PrestigeRule.keepUpgrades] - every upgrade. Keeps: the
/// currency, lifetime stats, achievements. Then refreshes the `prestige` multiplier and the income.
BigNumber? performPrestige(World world, BigTreasury wallet) {
  final rule = _first<PrestigeRule>(world);
  final stats = _first<IdleStats>(world);
  if (rule == null || stats == null) return null;
  final gain = rule.gainFor(stats.runEarned[rule.basedOn] ?? BigNumber.zero);
  if (gain < BigNumber.one) return null;

  final bank = wallet.of(rule.currency) + gain;
  wallet.amounts
    ..clear()
    ..addAll(rule.startingAmounts);
  wallet.amounts[rule.currency] = bank;

  final generators = world.storeOf<Generator>();
  for (var i = 0; i < generators.length; i++) {
    generators.denseAt(i).owned = 0;
  }
  if (!rule.keepUpgrades) {
    final upgrades = world.storeOf<Upgrade>();
    for (var i = 0; i < upgrades.length; i++) {
      upgrades.denseAt(i).purchased = false;
    }
  }

  stats.runEarned.clear();
  stats.prestigeCount++;

  final mods = _first<IdleModifiers>(world);
  mods?.stack.setMultiplier(
    prestigeSource,
    BigNumber.one + BigNumber.from(rule.bonusPerUnit) * bank,
  );
  recomputeIncome(world, wallet);
  return gain;
}

/// A goal with an optional reward, as data.
///
/// [stat] names what is measured (see [achievementValue]); the achievement unlocks when it reaches
/// [atLeast]. A [reward] above 1 becomes a permanent game-wide multiplier from the source
/// `achievement:<id>`.
class Achievement {
  final String id;
  final String? name;

  /// `lifetime:<resource>`, `run:<resource>`, `owned:<generatorId>`, `prestiges`, `taps` or `seconds`.
  final String stat;
  final BigNumber atLeast;
  final BigNumber reward;
  bool unlocked;

  Achievement({
    required this.id,
    required this.stat,
    required this.atLeast,
    this.name,
    BigNumber? reward,
    this.unlocked = false,
  }) : reward = reward ?? BigNumber.one;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'stat': stat,
    'atLeast': atLeast.toJson(),
    'reward': reward.toJson(),
    'unlocked': unlocked,
  };

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
    id: json['id'] as String,
    name: json['name'] as String?,
    stat: json['stat'] as String,
    atLeast: BigNumber.fromJson(json['atLeast'] as Object),
    reward: BigNumber.fromJson((json['reward'] ?? '1') as Object),
    unlocked: json['unlocked'] as bool? ?? false,
  );
}

/// The current value of an achievement [stat], or zero for an unknown one.
BigNumber achievementValue(World world, String stat) {
  final stats = _first<IdleStats>(world);
  final colon = stat.indexOf(':');
  final kind = colon < 0 ? stat : stat.substring(0, colon);
  final arg = colon < 0 ? '' : stat.substring(colon + 1);
  switch (kind) {
    case 'lifetime':
      return stats?.lifetimeEarned[arg] ?? BigNumber.zero;
    case 'run':
      return stats?.runEarned[arg] ?? BigNumber.zero;
    case 'prestiges':
      return BigNumber.from(stats?.prestigeCount ?? 0);
    case 'taps':
      return BigNumber.from(stats?.taps ?? 0);
    case 'seconds':
      return BigNumber.from(stats?.secondsPlayed ?? 0);
    case 'owned':
      final gens = world.storeOf<Generator>();
      for (var i = 0; i < gens.length; i++) {
        if (gens.denseAt(i).id == arg) {
          return BigNumber.from(gens.denseAt(i).owned);
        }
      }
      return BigNumber.zero;
  }
  return BigNumber.zero;
}

/// An achievement was just unlocked.
class AchievementUnlockedEvent {
  final String id;
  AchievementUnlockedEvent(this.id);
}

/// Unlocks every achievement whose goal is now met, applies rewards, emits an
/// [AchievementUnlockedEvent] for each, and returns their ids. Call it after purchases and every few
/// seconds - not every tick; it walks the (small) achievement list, not the world.
List<String> checkAchievements(World world, BigTreasury wallet) {
  final store = world.storeOf<Achievement>();
  final ids = [for (var i = 0; i < store.length; i++) store.entityAt(i)]
    ..sort();
  final unlocked = <String>[];
  var rewardsChanged = false;
  for (final e in ids) {
    final a = store.get(e)!;
    if (a.unlocked || achievementValue(world, a.stat) < a.atLeast) continue;
    a.unlocked = true;
    unlocked.add(a.id);
    if (a.reward > BigNumber.one) {
      _first<IdleModifiers>(
        world,
      )?.stack.setMultiplier('achievement:${a.id}', a.reward);
      rewardsChanged = true;
    }
    world.events.emit(AchievementUnlockedEvent(a.id));
  }
  if (rewardsChanged) recomputeIncome(world, wallet);
  return unlocked;
}

T? _first<T>(World world) {
  final s = world.storeOf<T>();
  return s.length == 0 ? null : s.denseAt(0);
}
