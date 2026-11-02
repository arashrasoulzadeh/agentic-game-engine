/// The simulation's seeded random numbers, with state that can be saved and
/// restored.
///
/// `dart:math`'s `Random` cannot expose its state, so a snapshot of a world
/// that used it could not reproduce what comes next. This is a small 32-bit
/// generator (mulberry32) whose entire state is one integer: copy [state] to
/// snapshot, assign it to roll back. All arithmetic stays below 2^53, so the
/// same seed gives the same sequence on the VM and in a web build.
///
/// Not cryptographic, and not the same stream as `DeterministicRandom`
/// (which wraps `dart:math` and keeps its sequences for existing replays).
class WorldRandom {
  static const int _mask = 0xFFFFFFFF;

  int _state;

  /// A generator starting from [seed] (only its low 32 bits are used).
  WorldRandom(int seed) : _state = seed & _mask;

  /// The full generator state. Assigning a value returned earlier makes the
  /// next draws repeat exactly.
  int get state => _state;
  set state(int value) => _state = value & _mask;

  static int _imul(int a, int b) =>
      (((a & 0xFFFF) * b) + ((((a >>> 16) * b) & 0xFFFF) << 16)) & _mask;

  /// A double in [0, 1).
  double nextDouble() {
    _state = (_state + 0x6D2B79F5) & _mask;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t = (t ^ ((t + _imul(t ^ (t >>> 7), t | 61)) & _mask)) & _mask;
    return ((t ^ (t >>> 14)) & _mask) / 4294967296;
  }

  /// An integer in [0, [max]); [max] must be between 1 and 2^32.
  int nextInt(int max) {
    if (max < 1 || max > 4294967296) {
      throw RangeError.range(max, 1, 4294967296, 'max');
    }
    return (nextDouble() * max).floor();
  }

  /// A fair coin.
  bool nextBool() => nextDouble() < 0.5;

  /// A double in [[min], [max]).
  double nextRange(double min, double max) => min + (max - min) * nextDouble();

  /// A uniformly chosen element of [items]; throws if it is empty.
  T pick<T>(List<T> items) {
    if (items.isEmpty) throw StateError('Cannot pick from an empty list.');
    return items[nextInt(items.length)];
  }
}
