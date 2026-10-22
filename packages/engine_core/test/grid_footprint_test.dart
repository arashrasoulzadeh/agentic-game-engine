import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridPosition p(int c, int r) => GridPosition(c, r);

/// A 10x10 grid with a wall across row 4 except the cells in [gap].
GridNavigator _nav(Set<int> gap) => GridNavigator(
  cols: 10,
  rows: 10,
  terrainCost: (c, r) => r == 4 && !gap.contains(c) ? null : 1,
);

World _world(GridNavigator nav) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  w.addSystem(OrderSystem.withNavigator(nav, attackRange: 1));
  return w;
}

EntityId _unit(World w, String team, int c, int r, {int? size, int ap = 30}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: 10, attack: 3));
  if (size != null) w.storeOf<GridFootprint>().set(e, GridFootprint(size));
  return e;
}

void main() {
  group('geometry', () {
    test('overlap is by shared cells', () {
      expect(footprintsOverlap(p(0, 0), 2, p(1, 1), 1), isTrue);
      expect(footprintsOverlap(p(0, 0), 2, p(2, 0), 1), isFalse);
      expect(footprintsOverlap(p(0, 0), 3, p(2, 2), 3), isTrue);
    });

    test('distance is measured edge to edge', () {
      expect(footprintDistance(p(0, 0), 1, p(1, 0), 1), 1);
      expect(
        footprintDistance(p(0, 0), 3, p(3, 0), 1),
        1,
        reason: 'adjacent to the big unit\'s edge',
      );
      expect(footprintDistance(p(0, 0), 3, p(5, 0), 1), 3);
      expect(footprintDistance(p(0, 0), 2, p(1, 1), 1), 0, reason: 'overlap');
      expect(
        footprintDistance(p(0, 0), 1, p(4, 7), 1),
        p(0, 0).chebyshev(p(4, 7)),
      );
    });

    test('the component round-trips and defaults to one cell', () {
      expect(GridFootprint.fromJson(GridFootprint(3).toJson()).size, 3);
      expect(GridFootprint.fromJson({}).size, 1);
      final w = World(width: 4, height: 4);
      registerCoreComponents(w);
      expect(w.components.isRegistered('gridFootprint'), isTrue);
    });
  });

  group('occupancy', () {
    test('another unit blocks every cell of its footprint', () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      final big = _unit(w, 'red', 4, 4, size: 2);
      final me = _unit(w, 'blue', 0, 0);
      final blocked = occupiedBy(
        w.storeOf<GridPosition>(),
        me,
        footprints: w.storeOf<GridFootprint>(),
      );
      expect(blocked(5, 5), isTrue);
      expect(blocked(4, 5), isTrue);
      expect(blocked(6, 4), isFalse);
      expect(w.storeOf<GridPosition>().get(big)!.col, 4);
    });

    test(
      'a big mover is blocked where its body would overlap, and by terrain',
      () {
        final w = World(width: 10, height: 10);
        registerCoreComponents(w);
        _unit(w, 'red', 5, 0);
        final big = _unit(w, 'blue', 0, 0, size: 2);
        final blocked = occupiedBy(
          w.storeOf<GridPosition>(),
          big,
          footprints: w.storeOf<GridFootprint>(),
          navigator: _nav({3}),
        );
        expect(
          blocked(4, 0),
          isTrue,
          reason: 'covers 4..5, and a unit stands on 5',
        );
        expect(blocked(2, 0), isFalse);
        expect(blocked(9, 0), isTrue, reason: 'would hang off the grid');
        expect(blocked(3, 3), isTrue, reason: 'row 4 under col 4 is wall');
      },
    );
  });

  group('movement', () {
    test('a 2x2 unit squeezes through a 2-wide gap but not a 1-wide one', () {
      final wide = _world(_nav({4, 5}));
      final a = _unit(wide, 'red', 4, 2, size: 2);
      _unit(wide, 'blue', 9, 9);
      startTurnBasedGame(wide, ['red', 'blue']);
      submitOrder(wide, a, const MoveOrder(4, 6));
      wide.step(0.1);
      expect(wide.storeOf<GridPosition>().get(a)!.row, 6);

      final narrow = _world(_nav({4}));
      final b = _unit(narrow, 'red', 4, 2, size: 2);
      _unit(narrow, 'blue', 9, 9);
      startTurnBasedGame(narrow, ['red', 'blue']);
      submitOrder(narrow, b, const MoveOrder(4, 6));
      narrow.step(0.1);
      expect(
        narrow.storeOf<GridPosition>().get(b)!.row,
        2,
        reason: 'could not get through',
      );
      expect(
        narrow.storeOf<OrderQueue>().get(b)!.orders,
        isEmpty,
        reason: 'order failed as blocked',
      );
    });

    test('a 1x1 unit still fits the 1-wide gap (existing behaviour)', () {
      final w = _world(_nav({4}));
      final a = _unit(w, 'red', 4, 2);
      _unit(w, 'blue', 9, 9);
      startTurnBasedGame(w, ['red', 'blue']);
      submitOrder(w, a, const MoveOrder(4, 6));
      w.step(0.1);
      expect(w.storeOf<GridPosition>().get(a)!.row, 6);
    });
  });

  group('combat', () {
    test(
      'a unit adjacent to a big target\'s far edge is in range without walking',
      () {
        final w = _world(_nav({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}));
        final big = _unit(w, 'blue', 2, 6, size: 3);
        final hitter = _unit(w, 'red', 5, 8, ap: 5);
        startTurnBasedGame(w, ['red', 'blue']);
        final hits = <AttackResolvedEvent>[];
        w.events.on<AttackResolvedEvent>(hits.add);
        submitOrder(w, hitter, AttackOrder(big));
        w.step(0.1);
        final pos = w.storeOf<GridPosition>().get(hitter)!;
        expect(
          [pos.col, pos.row],
          [5, 8],
          reason: '(5,8) touches the 2..4 x 6..8 body diagonally',
        );
        expect(hits.single.target, big);
      },
    );
  });

  group('real-time', () {
    test('a real-time unit cannot walk into a big unit\'s body', () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      final nav = GridNavigator(cols: 10, rows: 10, terrainCost: (c, r) => 1);
      w.addSystem(RealtimeOrderSystem(fields: FlowFieldCache(nav)));
      final big = _unit(w, 'blue', 3, 0, size: 2);
      final walker = w.spawn();
      w.storeOf<Team>().set(walker, Team('red'));
      w.storeOf<GridPosition>().set(walker, GridPosition(0, 0));
      w.storeOf<RealtimeStats>().set(walker, RealtimeStats(speed: 10));
      w.storeOf<OrderQueue>().set(walker, OrderQueue([const MoveOrder(6, 0)]));
      for (var i = 0; i < 80; i++) {
        w.step(0.1);
      }
      final cells = <int>{};
      for (var i = 0; i < 1; i++) {
        final p = w.storeOf<GridPosition>().get(walker)!;
        cells.add(p.col);
        expect(
          footprintsOverlap(p, 1, w.storeOf<GridPosition>().get(big)!, 2),
          isFalse,
          reason: 'walker at (${p.col},${p.row}) is inside the 2x2 body',
        );
      }
    });
  });
}
