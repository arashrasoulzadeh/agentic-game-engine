import '../ecs/entity.dart';

/// Uniform grid spatial hash for broad-phase collision — O(n) average
/// instead of O(n^2) pairwise checks. Validated at 10k entities in the
/// stress-test prototype before this engine was built.
class SpatialHash {
  final double cellSize;
  final Map<int, List<EntityId>> _cells = {};
  final int _cols;

  SpatialHash({required this.cellSize, required double worldWidth})
      : _cols = (worldWidth / cellSize).ceil() + 1;

  int _keyFor(double x, double y) {
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    return cy * _cols + cx;
  }

  void clear() => _cells.clear();

  void insert(EntityId id, double x, double y) {
    (_cells[_keyFor(x, y)] ??= []).add(id);
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
