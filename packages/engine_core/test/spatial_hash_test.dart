import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('forEachNearbyPair finds entities inserted into the same/adjacent cells', () {
    final hash = SpatialHash(cellSize: 10, worldWidth: 100);
    hash.insert(1, 0, 0);
    hash.insert(2, 5, 0);

    final pairs = <Set<int>>[];
    hash.forEachNearbyPair((a, b) => pairs.add({a, b}));

    expect(pairs.any((p) => p.containsAll({1, 2})), isTrue);
  });

  test('clear removes all inserted entities so no pairs are found afterward', () {
    final hash = SpatialHash(cellSize: 10, worldWidth: 100);
    hash.insert(1, 0, 0);
    hash.insert(2, 5, 0);

    hash.clear();

    var pairCount = 0;
    hash.forEachNearbyPair((a, b) => pairCount++);
    expect(pairCount, 0);
  });
}
