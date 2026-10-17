import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _open({bool diagonals = true, Set<(int, int)> walls = const {}, Map<(int, int), int> costs = const {}}) =>
    GridNavigator(
      cols: 6,
      rows: 6,
      diagonals: diagonals,
      terrainCost: (c, r) => walls.contains((c, r)) ? null : (costs[(c, r)] ?? 1),
    );

void main() {
  test('diagonal path is shorter than orthogonal-only', () {
    final d = _open().findPath(GridPosition(0, 0), GridPosition(3, 3))!;
    final o = _open(diagonals: false).findPath(GridPosition(0, 0), GridPosition(3, 3))!;
    expect(d.length, 3);
    expect(o.length, 6);
    expect((d.last.col, d.last.row), (3, 3));
  });

  test('path avoids expensive terrain', () {
    final nav = _open(costs: {(1, 0): 9, (1, 1): 9, (1, 2): 9});
    final path = nav.findPath(GridPosition(0, 1), GridPosition(2, 1))!;
    expect(path.map((p) => (p.col, p.row)), isNot(contains((1, 1))));
  });

  test('unreachable, blocked-goal, and same-cell cases', () {
    final wall = {for (var r = 0; r < 6; r++) (2, r)};
    final nav = _open(walls: wall);
    expect(nav.findPath(GridPosition(0, 0), GridPosition(5, 0)), isNull);
    expect(nav.findPath(GridPosition(0, 0), GridPosition(2, 0)), isNull);
    expect(nav.findPath(GridPosition(1, 1), GridPosition(1, 1)), isEmpty);
  });

  test('no diagonal corner cutting through a wall corner', () {
    final nav = _open(walls: {(1, 0)});
    final path = nav.findPath(GridPosition(0, 0), GridPosition(1, 1))!;
    expect(path.length, 2);
  });

  test('units block the path but not diagonal corners', () {
    final nav = _open();
    final path = nav.findPath(GridPosition(0, 0), GridPosition(2, 0),
        blocked: (c, r) => c == 1 && r == 0)!;
    expect(path.map((p) => (p.col, p.row)), isNot(contains((1, 0))));
    expect(path.length, 2);
  });

  test('reachable respects budget and terrain cost', () {
    final nav = _open(diagonals: false, costs: {(1, 0): 3});
    final r = nav.reachable(GridPosition(0, 0), 3);
    expect(r[(1, 0)], 3);
    expect(r[(0, 3)], 3);
    expect(r.containsKey((2, 0)), isFalse);
    expect(r.containsKey((0, 0)), isFalse);
  });

  test('fromTileMap treats solid tiles as walls and applies costs', () {
    final map = TileMap(
      cols: 3,
      rows: 1,
      tileWidth: 16,
      tileHeight: 16,
      tiles: [0, 1, 2],
      solidTileIds: {1},
    );
    final nav = GridNavigator.fromTileMap(map, terrainCosts: {2: 4});
    expect(nav.terrainCost(1, 0), isNull);
    expect(nav.terrainCost(2, 0), 4);
    expect(nav.terrainCost(0, 0), 1);
  });

  test('OrderSystem.withNavigator charges terrain cost and routes around units', () {
    final w = World(width: 10, height: 10);
    registerCoreComponents(w);
    w.addSystem(OrderSystem.withNavigator(_open(costs: {(1, 0): 3})));
    EntityId unit(String t, int c, int r, int ap) {
      final e = w.spawn();
      w.storeOf<Team>().set(e, Team(t));
      w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
      w.storeOf<GridPosition>().set(e, GridPosition(c, r));
      return e;
    }

    final a = unit('red', 0, 0, 4);
    unit('blue', 3, 3, 4);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, a, const MoveOrder(2, 0));
    w.step(0.1);
    final p = w.storeOf<GridPosition>().get(a)!;
    expect((p.col, p.row), (2, 0));
    expect(w.storeOf<ActionPoints>().get(a)!.current, lessThan(4));
  });
}
