import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav({Set<(int, int)> walls = const {}, int size = 12}) =>
    GridNavigator(
      cols: size,
      rows: size,
      terrainCost: (c, r) => walls.contains((c, r)) ? null : 1,
    );

void main() {
  group('formationCells', () {
    test(
      'the first cell is the target, then the nearest ring, all distinct',
      () {
        final cells = formationCells(_nav(), GridPosition(5, 5), 5);
        expect(cells, hasLength(5));
        expect((cells.first.col, cells.first.row), (5, 5));
        expect({for (final c in cells) (c.col, c.row)}, hasLength(5));
        for (final c in cells.skip(1)) {
          expect(
            c.chebyshev(GridPosition(5, 5)),
            1,
            reason: 'four more fit in the first ring',
          );
        }
      },
    );

    test('it spreads outward as the group grows, nearest first', () {
      final cells = formationCells(_nav(), GridPosition(5, 5), 12);
      expect(cells, hasLength(12));
      final distances = [
        for (final c in cells) c.chebyshev(GridPosition(5, 5)),
      ];
      expect(distances, [...distances]..sort());
      expect(distances.last, 2);
    });

    test('walls, the edge and taken cells are skipped', () {
      final cells = formationCells(
        _nav(walls: {(1, 0), (0, 1)}, size: 6),
        GridPosition(0, 0),
        3,
        taken: (c, r) => c == 1 && r == 1,
      );
      final set = {for (final c in cells) (c.col, c.row)};
      expect(set, isNot(contains((1, 0))));
      expect(set, isNot(contains((0, 1))));
      expect(set, isNot(contains((1, 1))));
      expect(set.every((c) => c.$1 >= 0 && c.$2 >= 0), isTrue);
    });

    test('cells cut off from the target by walls are not offered', () {
      final nav = _nav(walls: {for (var r = 0; r < 12; r++) (6, r)});
      final cells = formationCells(nav, GridPosition(3, 5), 40);
      expect(cells.every((c) => c.col < 6), isTrue);
    });

    test(
      'a request bigger than the free space returns what exists; zero returns nothing',
      () {
        final tiny = GridNavigator(cols: 2, rows: 2, terrainCost: (c, r) => 1);
        expect(formationCells(tiny, GridPosition(0, 0), 10), hasLength(4));
        expect(formationCells(_nav(), GridPosition(1, 1), 0), isEmpty);
        expect(formationCells(_nav(), GridPosition(1, 1), -3), isEmpty);
      },
    );

    test('the same input always yields the same cells', () {
      List<(int, int)> run() => [
        for (final c in formationCells(_nav(), GridPosition(4, 4), 9))
          (c.col, c.row),
      ];
      expect(run(), run());
    });
  });

  group('assignFormation', () {
    World setup(List<(int, int)> positions) {
      final w = World(width: 12, height: 12);
      registerCoreComponents(w);
      for (final p in positions) {
        w.storeOf<GridPosition>().set(w.spawn(), GridPosition(p.$1, p.$2));
      }
      return w;
    }

    test(
      'each cell goes to the nearest unassigned unit, so paths do not cross',
      () {
        final w = setup([(0, 0), (11, 0)]);
        final assignment = assignFormation(
          w,
          [0, 1],
          [GridPosition(10, 5), GridPosition(1, 5)],
        );
        expect(
          (assignment[0]!.col, assignment[0]!.row),
          (1, 5),
          reason: 'the west unit takes the west cell',
        );
        expect((assignment[1]!.col, assignment[1]!.row), (10, 5));
      },
    );

    test(
      'more cells than units, or units without a position, are tolerated',
      () {
        final w = setup([(0, 0)]);
        final a = assignFormation(
          w,
          [0],
          [GridPosition(1, 1), GridPosition(2, 2)],
        );
        expect(a, hasLength(1));
        expect(assignFormation(w, [99], [GridPosition(1, 1)]), isEmpty);
      },
    );
  });

  group('commandSelected with a formation', () {
    World group(int n) {
      final w = World(width: 12, height: 12);
      registerCoreComponents(w);
      for (var i = 0; i < n; i++) {
        spawnRealtimeUnit(w, team: 'red', col: i, row: 0);
      }
      selectInBox(w, 0, 0, n, 0, team: 'red');
      return w;
    }

    List<(int, int)> targets(World w) => [
      for (final e in selectedEntities(w))
        (
          (w.storeOf<OrderQueue>().get(e)!.orders.single as MoveOrder).col,
          (w.storeOf<OrderQueue>().get(e)!.orders.single as MoveOrder).row,
        ),
    ];

    test(
      'without a formation everyone gets the same cell (the old behaviour)',
      () {
        final w = group(4);
        expect(commandSelected(w, 8, 8, team: 'red'), 4);
        expect(targets(w).toSet(), {(8, 8)});
      },
    );

    test('with a formation they get distinct cells around the target', () {
      final w = group(4);
      expect(commandSelected(w, 8, 8, team: 'red', formation: _nav()), 4);
      final cells = targets(w);
      expect(cells.toSet(), hasLength(4));
      for (final c in cells) {
        expect(
          GridPosition(c.$1, c.$2).chebyshev(GridPosition(8, 8)),
          lessThanOrEqualTo(1),
        );
      }
    });

    test('a single unit, and attack orders, ignore the formation', () {
      final one = group(1);
      commandSelected(one, 8, 8, team: 'red', formation: _nav());
      expect(targets(one), [(8, 8)]);

      final w = group(3);
      final foe = spawnRealtimeUnit(w, team: 'blue', col: 9, row: 9);
      commandSelected(w, 9, 9, team: 'red', formation: _nav());
      for (final e in selectedEntities(w)) {
        expect(
          (w.storeOf<OrderQueue>().get(e)!.orders.single as AttackOrder).target,
          foe,
        );
      }
    });

    test('cells held by idle units are avoided', () {
      final w = group(3);
      spawnRealtimeUnit(w, team: 'red', col: 8, row: 8);
      commandSelected(w, 8, 8, team: 'red', formation: _nav());
      expect(targets(w), isNot(contains((8, 8))));
    });
  });
}
