import 'dart:math';

/// A seeded RNG wrapper for reproducible simulation runs -- an agent
/// replaying/debugging a physics- or AI-heavy game needs the exact same
/// random sequence on every run given the same seed, which a bare
/// `Random()` (unseeded) or an ad-hoc `Random(seed)` scattered across
/// systems can't guarantee: every call site would need to agree on
/// seeding it the same way. `DeterministicRandom` centralizes that: one
/// seed, [reset] replays the identical sequence from the start without
/// re-constructing the object (so code holding a reference keeps
/// working after a reset), and [seed] is always readable for saving
/// alongside a replay recording.
class DeterministicRandom {
  final int seed;
  Random _random;

  DeterministicRandom(this.seed) : _random = Random(seed);

  /// Re-seeds back to [seed], so the exact same sequence of subsequent
  /// calls repeats from here -- used when re-running a recorded replay.
  void reset() => _random = Random(seed);

  int nextInt(int max) => _random.nextInt(max);

  double nextDouble() => _random.nextDouble();

  bool nextBool() => _random.nextBool();

  /// A double in `[min, max)`, the common case of `nextDouble` scaled
  /// into a game-relevant range (spawn jitter, damage variance, etc.)
  /// rather than every call site re-deriving the same `min + (max -
  /// min) * nextDouble()` arithmetic.
  double nextRange(double min, double max) => min + (max - min) * nextDouble();
}
