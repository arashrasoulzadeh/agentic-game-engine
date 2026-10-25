import 'dart:async';

import 'package:engine_core/engine_core.dart';
import 'package:flutter/foundation.dart';

import 'package:engine_core/engine_core_idle.dart';

import 'idle_sfx.dart';

/// Runs an idle game's [world] and tells widgets when to redraw.
///
/// It owns the clock: [start] steps the world on a timer (default every 100 ms, with the real elapsed time
/// so a slow frame does not lose income) and notifies listeners at that rate - a UI that rebuilt every
/// frame would waste work on numbers that change imperceptibly. Widgets listen to it and read state from
/// [world] and [wallet]; every action goes through its methods so listeners are told.
///
/// Tests call [tick] directly instead of waiting on a timer.
class IdleController extends ChangeNotifier {
  IdleController({
    required this.world,
    this.style = NumberStyle.suffix,
    this.tickInterval = const Duration(milliseconds: 100),
    this.team = 'player',
    this.analytics,
    this.sfx,
    this.strings,
    this.decimalSeparator = '.',
  });

  final World world;

  /// The game's resources: the world's first [BigTreasury]. Looked up each time rather than held, so
  /// restoring a save (which replaces the component) never leaves the controller on a stale copy.
  BigTreasury get wallet {
    final store = world.storeOf<BigTreasury>();
    if (store.length == 0) {
      throw StateError(
        'The world has no BigTreasury; add one before using IdleController.',
      );
    }
    return store.denseAt(0);
  }

  /// How big numbers are written everywhere in the UI.
  NumberStyle style;

  /// How often [start] steps and notifies.
  final Duration tickInterval;

  /// Whose technologies unlock purchases.
  final String team;

  /// The decimal mark in every formatted number (`,` for many locales). Games read it from their
  /// localisation and set it here, so no widget needs to know about locales.
  String decimalSeparator;

  /// Reports purchases and prestiges; null sends nothing.
  final IdleAnalytics? analytics;

  /// One-shot buy / prestige / golden / tap feedback; null plays nothing.
  final IdleSfx? sfx;

  /// Optional localisation for [nameKey] fields on generators / upgrades / etc.
  StringTable? strings;

  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  Duration _last = Duration.zero;

  /// Bumped only by player actions (buy, prestige, style change, …), not by [tick].
  ///
  /// [ThrottledListenableBuilder] rebuilds immediately when this changes and only
  /// throttles the 10 Hz tick, so a purchase never waits on the rebuild interval.
  int get urgentGeneration => _urgent;
  int _urgent = 0;

  void _notifyUrgent() {
    _urgent++;
    notifyListeners();
  }

  /// Changes how big numbers are written and tells every listening widget at once.
  void setStyle(NumberStyle value) {
    if (value == style) return;
    style = value;
    _notifyUrgent();
  }

  /// Changes the decimal mark and tells every listening widget at once.
  void setDecimalSeparator(String value) {
    if (value == decimalSeparator) return;
    decimalSeparator = value;
    _notifyUrgent();
  }

  /// Resolves a display label: [nameKey] via [strings], else [name], else [id].
  String label(String id, {String? name, String? nameKey}) {
    if (nameKey != null && strings != null) {
      return strings!.resolve(nameKey);
    }
    return name ?? id;
  }

  /// Swaps the string table (or clears it) and refreshes labels.
  void setStrings(StringTable? value) {
    if (identical(value, strings)) return;
    strings = value;
    _notifyUrgent();
  }

  final Map<String, String> _formatted = {};

  /// How many distinct formatted strings are remembered (observable for tests).
  int get formatCacheSize => _formatted.length;

  /// Writes [value] in the controller's current [style].
  ///
  /// Results are remembered: a list of hundreds of rows asks for the same few numbers every frame, and
  /// formatting a big number is real work. The key includes the style and separator, so changing either
  /// (even by assigning the public fields) simply misses the cache; it is emptied when it grows past a
  /// thousand entries rather than tracking recency.
  String format(BigNumber value, {int decimals = 2}) {
    final key = '${style.index}|$decimalSeparator|$decimals|${value.toJson()}';
    final hit = _formatted[key];
    if (hit != null) return hit;
    if (_formatted.length >= 1024) _formatted.clear();
    return _formatted[key] = formatBigNumber(
      value,
      style: style,
      decimals: decimals,
      decimalSeparator: decimalSeparator,
    );
  }

  /// Begins stepping the world in real time.
  void start() {
    if (_timer != null) return;
    _clock.start();
    _last = _clock.elapsed;
    _timer = Timer.periodic(tickInterval, (_) {
      final now = _clock.elapsed;
      final dt = (now - _last).inMicroseconds / Duration.microsecondsPerSecond;
      _last = now;
      tick(dt);
    });
  }

  /// Stops the timer (also when the app is backgrounded; catch up on resume instead).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  /// Tells listeners the world changed outside the controller's own methods (a restored save).
  void refresh() => _notifyUrgent();

  /// Advances the world by [dt] seconds and notifies listeners (tick only — not [urgentGeneration]).
  void tick(double dt) {
    world.step(dt);
    notifyListeners();
  }

  /// Buys [count] of [generator] (null for as many as affordable). See [buyGenerator].
  BuyResult buy(EntityId generator, {int? count = 1}) {
    final r = buyGenerator(world, wallet, generator, count: count, team: team);
    if (r.ok) {
      analytics?.purchase(
        world.storeOf<Generator>().get(generator)!.id,
        r.bought,
        r.spent,
      );
      sfx?.onBuy?.call();
      checkAchievements(world, wallet);
      _notifyUrgent();
    }
    return r;
  }

  /// Buys [upgrade] once. See [buyUpgrade].
  BuyResult buyUpgradeById(EntityId upgrade) {
    final r = buyUpgrade(world, wallet, upgrade, team: team);
    if (r.ok) {
      analytics?.purchase(
        world.storeOf<Upgrade>().get(upgrade)!.id,
        r.bought,
        r.spent,
      );
      sfx?.onUpgrade?.call();
      checkAchievements(world, wallet);
      _notifyUrgent();
    }
    return r;
  }

  /// A manual tap. See [tapEarn].
  BigNumber tap({String resource = 'coins', BigNumber? amount}) {
    final earned = tapEarn(world, wallet, resource: resource, amount: amount);
    sfx?.onTap?.call();
    checkAchievements(world, wallet);
    _notifyUrgent();
    return earned;
  }

  /// Prestiges layer [ruleId] (the first by default) if worthwhile; returns the gain or null. See [performPrestige].
  BigNumber? prestige([String? ruleId]) {
    final gain = performPrestige(world, wallet, ruleId);
    if (gain != null) {
      analytics?.prestige(
        gain,
        world.storeOf<IdleStats>().denseAt(0).prestigeCount,
      );
      sfx?.onPrestige?.call();
      _notifyUrgent();
    }
    return gain;
  }

  /// Claims the showing golden offer (see [claimGolden]); returns what it gave, or null if none was showing.
  GoldenReward? claimGoldenOffer() {
    final reward = claimGolden(world, wallet);
    if (reward != null) {
      sfx?.onGolden?.call();
      _notifyUrgent();
    }
    return reward;
  }

  /// Starts challenge [id] (see [startChallenge]); notifies listeners when it started.
  bool startChallengeById(String id) {
    final ok = startChallenge(world, wallet, id);
    if (ok) _notifyUrgent();
    return ok;
  }

  /// Gives up the running challenge without a reward.
  bool abandonRunningChallenge() {
    final ok = abandonChallenge(world, wallet);
    if (ok) _notifyUrgent();
    return ok;
  }

  /// Buys research [node] once (see [buyResearch]).
  BuyResult buyResearchById(EntityId node) {
    final r = buyResearch(world, wallet, node, team: team);
    if (r.ok) {
      sfx?.onUpgrade?.call();
      _notifyUrgent();
    }
    return r;
  }

  /// Buys a [TimeWarpOffer] (see [buyTimeWarp]).
  BuyResult buyTimeWarpById(EntityId offer) {
    final r = buyTimeWarp(world, wallet, offer);
    if (r.ok) {
      sfx?.onBuy?.call();
      _notifyUrgent();
    }
    return r;
  }

  /// Every generator entity in a stable order.
  List<EntityId> get generatorIds {
    final s = world.storeOf<Generator>();
    return [for (var i = 0; i < s.length; i++) s.entityAt(i)]..sort();
  }

  /// Every upgrade entity in a stable order.
  List<EntityId> get upgradeIds {
    final s = world.storeOf<Upgrade>();
    return [for (var i = 0; i < s.length; i++) s.entityAt(i)]..sort();
  }

  /// Declared resource ids (including zero balances), sorted for a stable header.
  List<String> get resourceIds => wallet.amounts.keys.toList()..sort();

  /// Prestige layer ids in store order (one [PrestigePanel] per id).
  List<String> get prestigeRuleIds {
    final s = world.storeOf<PrestigeRule>();
    return [for (var i = 0; i < s.length; i++) s.denseAt(i).id];
  }

  /// Research node entities in a stable order.
  List<EntityId> get researchIds {
    final s = world.storeOf<ResearchNode>();
    return [for (var i = 0; i < s.length; i++) s.entityAt(i)]..sort();
  }

  /// Time-warp offer entities in a stable order.
  List<EntityId> get timeWarpIds {
    final s = world.storeOf<TimeWarpOffer>();
    return [for (var i = 0; i < s.length; i++) s.entityAt(i)]..sort();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
