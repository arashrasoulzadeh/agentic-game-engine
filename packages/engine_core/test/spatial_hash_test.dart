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

  test(
      'the same SpatialHash instance works correctly across repeated clear()+insert() '
      'cycles into the same cells -- regression for clear() now emptying buckets in '
      'place (reusing their List objects, for CollisionSystem to reuse one SpatialHash '
      'across ticks) instead of dropping map entries entirely',
      tags: ['regression'], () {
    final hash = SpatialHash(cellSize: 10, worldWidth: 100);

    hash.insert(1, 0, 0);
    hash.insert(2, 5, 0);
    var pairs = <Set<int>>[];
    hash.forEachNearbyPair((a, b) => pairs.add({a, b}));
    expect(pairs, [
      {1, 2},
    ]);

    // A full clear+reinsert cycle with entirely different entity ids in
    // the exact same cells -- the old ids must not linger.
    hash.clear();
    hash.insert(10, 0, 0);
    hash.insert(20, 5, 0);
    hash.insert(30, 6, 0);
    pairs = <Set<int>>[];
    hash.forEachNearbyPair((a, b) => pairs.add({a, b}));

    expect(pairs.any((p) => p.contains(1) || p.contains(2)), isFalse,
        reason: 'entities from before the clear() must not leak into this cycle\'s results');
    expect(pairs.length, 3, reason: '10/20/30 are all mutually adjacent -- 3 pairs');

    // A third cycle, again reusing the same cells, to rule out any
    // one-clear-only fluke.
    hash.clear();
    var thirdCycleCount = 0;
    hash.forEachNearbyPair((a, b) => thirdCycleCount++);
    expect(thirdCycleCount, 0);
  });
}
