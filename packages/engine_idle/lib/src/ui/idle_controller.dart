import 'dart:async';

import 'package:engine_core/engine_core.dart';
import 'package:flutter/foundation.dart';

import '../active_play.dart';
import '../components.dart';
import '../economy.dart';
import '../progression.dart';

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

  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  Duration _last = Duration.zero;

  /// Writes [value] in the controller's current [style].
  String format(BigNumber value, {int decimals = 2}) =>
      formatBigNumber(value, style: style, decimals: decimals);

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
  void refresh() => notifyListeners();

  /// Advances the world by [dt] seconds and notifies listeners.
  void tick(double dt) {
    world.step(dt);
    notifyListeners();
  }

  /// Buys [count] of [generator] (null for as many as affordable). See [buyGenerator].
  BuyResult buy(EntityId generator, {int? count = 1}) {
    final r = buyGenerator(world, wallet, generator, count: count, team: team);
    if (r.ok) {
      checkAchievements(world, wallet);
      notifyListeners();
    }
    return r;
  }

  /// Buys [upgrade] once. See [buyUpgrade].
  BuyResult buyUpgradeById(EntityId upgrade) {
    final r = buyUpgrade(world, wallet, upgrade, team: team);
    if (r.ok) {
      checkAchievements(world, wallet);
      notifyListeners();
    }
    return r;
  }

  /// A manual tap. See [tapEarn].
  BigNumber tap({String resource = 'coins', BigNumber? amount}) {
    final earned = tapEarn(world, wallet, resource: resource, amount: amount);
    checkAchievements(world, wallet);
    notifyListeners();
    return earned;
  }

  /// Prestiges if worthwhile; returns the gain or null. See [performPrestige].
  BigNumber? prestige() {
    final gain = performPrestige(world, wallet);
    if (gain != null) notifyListeners();
    return gain;
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

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
