import '../ecs/entity.dart';

/// Uniform grid spatial hash for broad-phase collision — O(n) average
/// instead of O(n^2) pairwise checks. Validated at 10k entities in the
/// stress-test prototype before this engine was built.
class SpatialHash {
  final double cellSize;
  final Map<int, List<EntityId>> _cells = {};
  final int _cols;

  /// Keys actually touched since the last [clear] — [forEachNearbyPair]
  /// only ever needs to look at these, and [clear] only ever needs to
  /// reset these, so both stay bounded by *this cycle's* occupancy
  /// instead of growing with every distinct cell a `CollisionSystem`
  /// reusing one `SpatialHash` across many ticks has ever touched over
  /// the game's whole lifetime (moving entities would otherwise touch
  /// more and more distinct cells run after run, making both of those
  /// operations slowly regress the longer the game has been running —
  /// caught by this engine's own `collision_system_benchmark.dart`
  /// regressing at low entity counts when an earlier version of this
  /// class just left every bucket sitting in `_cells` forever).
  final List<int> _activeKeys = [];

  /// Emptied buckets [clear] recycles here instead of discarding, so
  /// [insert] can hand a cell that's newly active *this* cycle an
  /// already-allocated `List` instead of allocating a fresh one —
  /// bounded by the largest number of simultaneously-active cells this
  /// instance has ever seen in one cycle, not by total cells ever
  /// touched across its lifetime.
  final List<List<EntityId>> _bucketPool = [];

  SpatialHash({required this.cellSize, required double worldWidth})
      : _cols = (worldWidth / cellSize).ceil() + 1;

  int _keyFor(double x, double y) {
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    return cy * _cols + cx;
  }

  /// Resets this hash to empty, ready for the next `insert`/
  /// `forEachNearbyPair` cycle — recycles each active cell's bucket
  /// `List` into [_bucketPool] (see its own doc comment for why
  /// pooling like this, rather than either allocating fresh buckets
  /// every cycle or leaving old ones sitting in `_cells` forever, is
  /// what actually keeps this both allocation-light *and* bounded by
  /// current occupancy). `CollisionSystem` (this hash's one real
  /// caller) reuses one `SpatialHash` instance across ticks and calls
  /// this between them instead of constructing a fresh instance every
  /// single tick — confirmed measurably faster at realistic entity
  /// counts via `collision_system_benchmark.dart`.
  void clear() {
    for (final key in _activeKeys) {
      final bucket = _cells.remove(key);
      if (bucket != null) {
        bucket.clear();
        _bucketPool.add(bucket);
      }
    }
    _activeKeys.clear();
  }

  void insert(EntityId id, double x, double y) {
    final key = _keyFor(x, y);
    var bucket = _cells[key];
    if (bucket == null) {
      bucket = _bucketPool.isNotEmpty ? _bucketPool.removeLast() : <EntityId>[];
      _cells[key] = bucket;
      _activeKeys.add(key);
    }
    bucket.add(id);
  }

  /// Runs [onPair] for every entity pair that might collide (same or
  /// neighboring cell). Caller does the actual distance check.
  void forEachNearbyPair(void Function(EntityId a, EntityId b) onPair) {
    for (final entry in _cells.entries) {
      final cx = entry.key % _cols;
      final cy = entry.key ~/ _cols;
      for (var dx = 0; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          if (dx == 0 && dy < 0) continue; // avoid double-visiting pairs
          final neighborKey = (cy + dy) * _cols + (cx + dx);
          final neighbors = _cells[neighborKey];
          if (neighbors == null) continue;
          final sameCell = neighborKey == entry.key;
          final bucket = entry.value;
          for (var i = 0; i < bucket.length; i++) {
            final startJ = sameCell ? i + 1 : 0;
            for (var j = startJ; j < neighbors.length; j++) {
              onPair(bucket[i], neighbors[j]);
            }
          }
        }
      }
    }
  }
}
