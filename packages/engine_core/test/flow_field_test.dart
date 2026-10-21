import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav({
  int size = 10,
  bool diagonals = true,
  Set<(int, int)> walls = const {},
  Map<(int, int), int> costs = const {},
}) => GridNavigator(
  cols: size,
  rows: size,
  diagonals: diagonals,
  terrainCost: (c, r) => walls.contains((c, r)) ? null : (costs[(c, r)] ?? 1),
);

List<GridPosition> _walk(
  FlowField f,
  GridPosition from, {
  bool Function(int, int)? blocked,
  int limit = 200,
}) {
  final path = <GridPosition>[];
  var at = from;
  for (var i = 0; i < limit; i++) {
    final next = f.nextStep(at, blocked: blocked);
    if (next == null) break;
    path.add(next);
    at = next;
  }
  return path;
}

void main() {
  group('FlowField', () {
    test(
      'goal costs 0; cost grows with distance; uses the navigator\'s diagonals',
      () {
        final f = FlowField.build(_nav(), 5, 5);
        expect(f.costAt(5, 5), 0);
        expect(f.costAt(6, 6), 1);
        expect(f.costAt(8, 5), 3);
        expect(f.costAt(8, 8), 3);
        final orthogonal = FlowField.build(_nav(diagonals: false), 5, 5);
        expect(orthogonal.costAt(8, 8), 6);
      },
    );

    test('following the field reaches the goal along a shortest path', () {
      final nav = _nav(walls: {for (var r = 0; r < 8; r++) (4, r)});
      final f = FlowField.build(nav, 8, 1);
      final from = GridPosition(1, 1);
      final path = _walk(f, from);
      expect((path.last.col, path.last.row), (8, 1));
      final viaFindPath = nav.findPath(from, GridPosition(8, 1))!;
      expect(path.length, viaFindPath.length, reason: 'same length as A*');
      for (final p in path) {
        expect(nav.terrainCost(p.col, p.row), isNotNull);
      }
    });

    test('terrain costs steer the route around expensive cells', () {
      final nav = _nav(size: 5, diagonals: false, costs: {(2, 2): 9});
      final f = FlowField.build(nav, 4, 2);
      final path = _walk(f, GridPosition(0, 2));
      expect(path.any((p) => p.col == 2 && p.row == 2), isFalse);
      expect((path.last.col, path.last.row), (4, 2));
    });

    test(
      'unreachable cells, impassable goals and out-of-bounds are reported, not thrown',
      () {
        final enclosed = _nav(size: 5, walls: {(1, 0), (0, 1), (1, 1)});
        final f = FlowField.build(enclosed, 4, 4);
        expect(f.reaches(0, 0), isFalse);
        expect(f.nextStep(GridPosition(0, 0)), isNull);
        expect(f.costAt(-1, 0), FlowField.unreachable);
        expect(f.costAt(99, 99), FlowField.unreachable);

        final blockedGoal = FlowField.build(_nav(walls: {(5, 5)}), 5, 5);
        expect(blockedGoal.reaches(0, 0), isFalse);
        expect(FlowField.build(_nav(), 50, 50).reaches(0, 0), isFalse);
      },
    );

    test('at the goal there is no next step', () {
      expect(
        FlowField.build(_nav(), 3, 3).nextStep(GridPosition(3, 3)),
        isNull,
      );
    });

    test(
      'blocked cells (other units) are stepped around, and a fully blocked unit waits',
      () {
        final f = FlowField.build(_nav(), 9, 0);
        final step = f.nextStep(
          GridPosition(0, 0),
          blocked: (c, r) => c == 1 && r == 0,
        )!;
        expect((step.col, step.row), isNot((1, 0)));
        expect(f.costAt(step.col, step.row), lessThan(f.costAt(0, 0)));

        expect(f.nextStep(GridPosition(0, 0), blocked: (c, r) => true), isNull);
      },
    );

    test('a one-wide corridor forces the route', () {
      final nav = GridNavigator(
        cols: 10,
        rows: 3,
        terrainCost: (c, r) => r == 1 ? 1 : null,
      );
      final f = FlowField.build(nav, 9, 1);
      final path = _walk(f, GridPosition(0, 1));
      expect(path.length, 9);
      expect(path.every((p) => p.row == 1), isTrue);
    });
  });

  group('FlowFieldCache', () {
    test('units sent to the same cell share one field', () {
      final cache = FlowFieldCache(_nav());
      final a = cache.fieldFor(3, 3);
      final b = cache.fieldFor(3, 3);
      expect(identical(a, b), isTrue);
      expect(cache.builds, 1);
      cache.fieldFor(4, 4);
      expect(cache.builds, 2);
      expect(cache.size, 2);
    });

    test('evicts the least recently used field beyond capacity', () {
      final cache = FlowFieldCache(_nav(), capacity: 2);
      cache.fieldFor(1, 1);
      cache.fieldFor(2, 2);
      cache.fieldFor(1, 1); // refresh (1,1)
      cache.fieldFor(3, 3); // evicts (2,2)
      expect(cache.size, 2);
      cache.fieldFor(1, 1);
      expect(cache.builds, 3, reason: '(1,1) survived');
      cache.fieldFor(2, 2);
      expect(cache.builds, 4, reason: '(2,2) was evicted and rebuilt');
    });

    test('invalidate drops everything so changed terrain is re-read', () {
      var wall = false;
      final nav = GridNavigator(
        cols: 5,
        rows: 1,
        terrainCost: (c, r) => c == 2 && wall ? null : 1,
      );
      final cache = FlowFieldCache(nav);
      expect(cache.fieldFor(4, 0).reaches(0, 0), isTrue);
      wall = true;
      expect(
        cache.fieldFor(4, 0).reaches(0, 0),
        isTrue,
        reason: 'stale until invalidated',
      );
      cache.invalidate();
      expect(cache.fieldFor(4, 0).reaches(0, 0), isFalse);
    });
  });

  test('a hundred units to one goal cost one field build and all arrive', () {
    final nav = _nav(size: 30, walls: {for (var r = 0; r < 25; r++) (15, r)});
    final cache = FlowFieldCache(nav);
    final units = [for (var i = 0; i < 100; i++) GridPosition(i % 10, i ~/ 10)];
    for (final u in units) {
      final f = cache.fieldFor(28, 2);
      var guard = 0;
      while (guard++ < 200) {
        final n = f.nextStep(u);
        if (n == null) break;
        u.col = n.col;
        u.row = n.row;
      }
      expect((u.col, u.row), (28, 2));
    }
    expect(cache.builds, 1);
  });
}
