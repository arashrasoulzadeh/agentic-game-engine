import 'dart:convert';

import '../ecs/world.dart';
import 'world_snapshot.dart';

/// Applies one tick's inputs (player id -> input) to the world, before the
/// systems run. Must be a pure function of its arguments and the world.
typedef InputApplier =
    void Function(World world, Map<int, Map<String, dynamic>> inputs);

/// Rollback netcode: simulate ahead with *predicted* remote inputs, and when the
/// real input arrives and differs, rewind to that tick and re-simulate with it.
///
/// Correctness rests on **determinism**: given the same world and inputs, a tick
/// must produce the same result. Use `DeterministicRandom`, no wall-clock time
/// and no iteration over unordered sets in rule code; the engine's turn-based
/// rules already follow this. If your systems aren't deterministic, rollback will
/// *appear* to work and then desync - [correctState] (from an authoritative peer)
/// is the safety net.
///
/// The session owns when ticks run: call [advance] once per tick instead of
/// `world.step`.
class RollbackSession {
  RollbackSession({
    required this.world,
    required this.applyInputs,
    this.fixedDt = 1 / 60,
    this.maxRollbackTicks = 32,
  });

  final World world;
  final InputApplier applyInputs;
  final double fixedDt;

  /// How far back an input may still correct history. Older inputs are counted
  /// in [lateInputs] and ignored: keeping unbounded history costs memory, and a
  /// peer that far behind needs a state resync, not a replay.
  final int maxRollbackTicks;

  final Map<int, Map<int, Map<String, dynamic>>> _confirmed = {};
  final Map<int, Map<int, Map<String, dynamic>>> _used = {};
  final Map<int, WorldSnapshot> _snapshots = {};
  int? _rollbackFrom;

  /// Inputs that arrived for a tick older than [maxRollbackTicks] and were ignored.
  int lateInputs = 0;

  /// Total ticks re-simulated by rollbacks so far (a measure of misprediction cost).
  int resimulatedTicks = 0;

  int get tick => world.tick;

  /// True if a late input changed history and [reconcile] has work to do.
  bool get needsReconcile => _rollbackFrom != null;

  /// The input the session would use for [player] at [tick]: the confirmed one,
  /// else a prediction -- the player's most recent confirmed input at or before
  /// that tick (people hold buttons, so "same as last time" is usually right).
  Map<String, dynamic> inputFor(int player, int tick) {
    final confirmed = _confirmed[tick]?[player];
    if (confirmed != null) return confirmed;
    for (var t = tick - 1; t >= tick - maxRollbackTicks && t >= 0; t--) {
      final earlier = _confirmed[t]?[player];
      if (earlier != null) return earlier;
    }
    return const {};
  }

  /// Records the real input for [player] at [tickNo]. If that tick was already
  /// simulated with a different (predicted) input, marks history for rollback.
  /// Returns false if it was too old to apply.
  bool addInput(int player, int tickNo, Map<String, dynamic> input) {
    if (tickNo < world.tick - maxRollbackTicks) {
      lateInputs++;
      return false;
    }
    (_confirmed[tickNo] ??= {})[player] = input;
    if (tickNo < world.tick) {
      final used = _used[tickNo]?[player];
      if (used == null || _key(used) != _key(input)) {
        _rollbackFrom = _rollbackFrom == null || tickNo < _rollbackFrom!
            ? tickNo
            : _rollbackFrom;
      }
    }
    return true;
  }

  /// Simulates one tick for the given [players], predicting any input not yet
  /// confirmed.
  void advance(Iterable<int> players) {
    final t = world.tick;
    _snapshots[t] = WorldSnapshot.capture(world);
    final inputs = {for (final p in players) p: inputFor(p, t)};
    _used[t] = inputs;
    applyInputs(world, inputs);
    world.step(fixedDt);
    _prune();
  }

  /// If history was invalidated, rewinds to the earliest affected tick and
  /// re-simulates up to where the world was, using the now-known inputs. Returns
  /// how many ticks were replayed (0 when nothing changed).
  int reconcile(Iterable<int> players) {
    final from = _rollbackFrom;
    if (from == null) return 0;
    _rollbackFrom = null;
    final snapshot = _snapshots[from];
    if (snapshot == null) return 0;
    final target = world.tick;
    snapshot.restoreInto(world);
    final replayed = target - from;
    while (world.tick < target) {
      advance(players);
    }
    resimulatedTicks += replayed;
    return replayed;
  }

  /// Aligns with an authoritative state (from a server). If it is for a tick we
  /// still hold, replaces our version of that tick and replays forward from it;
  /// if we are *behind* it, jumps to it. Ticks we can no longer replay are
  /// simply restored (a visible correction, but never a permanent desync).
  /// Returns the ticks replayed.
  int correctState(WorldSnapshot authoritative, Iterable<int> players) {
    final target = world.tick;
    authoritative.restoreInto(world);
    _snapshots[authoritative.tick] = authoritative;
    _rollbackFrom = null;
    if (authoritative.tick >= target) return 0;
    final replayed = target - authoritative.tick;
    if (replayed > maxRollbackTicks) return 0;
    while (world.tick < target) {
      advance(players);
    }
    resimulatedTicks += replayed;
    return replayed;
  }

  void _prune() {
    final oldest = world.tick - maxRollbackTicks - 1;
    for (final map in [_confirmed, _used, _snapshots]) {
      map.removeWhere((t, _) => t < oldest);
    }
  }

  static String _key(Map<String, dynamic> m) => jsonEncode(_sorted(m));

  static Object? _sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _sorted(v[k])};
    }
    if (v is List) return v.map(_sorted).toList();
    return v;
  }
}
