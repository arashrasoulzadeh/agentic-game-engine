import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  return w;
}

EntityId _unit(World w, String team, int c, int r) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(5, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  return e;
}

void main() {
  test('selectAtCell picks only the active team and replaces selection', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0);
    final b = _unit(w, 'red', 1, 0);
    final x = _unit(w, 'blue', 2, 0);
    startTurnBasedGame(w, ['red', 'blue']);
    expect(selectAtCell(w, 2, 0), isNull);
    expect(selectAtCell(w, 0, 0), a);
    expect(selectAtCell(w, 1, 0), b);
    expect(selectedEntities(w), [b]);
    selectAtCell(w, 0, 0, additive: true);
    expect(selectedEntities(w).toSet(), {a, b});
    expect(w.storeOf<Selected>().has(x), isFalse);
  });

  test('empty-cell tap leaves selection untouched', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0);
    startTurnBasedGame(w, ['red']);
    selectAtCell(w, 0, 0);
    expect(selectAtCell(w, 4, 4), isNull);
    expect(selectedEntities(w), [a]);
  });

  test('selectInBox accepts corners in any order and ignores other teams', () {
    final w = _world();
    final a = _unit(w, 'red', 1, 1);
    final b = _unit(w, 'red', 2, 2);
    _unit(w, 'red', 5, 5);
    _unit(w, 'blue', 1, 2);
    startTurnBasedGame(w, ['red', 'blue']);
    expect(selectInBox(w, 3, 3, 0, 0), 2);
    expect(selectedEntities(w).toSet(), {a, b});
    expect(selectInBox(w, 8, 8, 9, 9), 0);
    expect(selectedEntities(w).toSet(), {a, b});
  });

  test('commandSelected moves to empty cells and attacks enemies', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0);
    final b = _unit(w, 'red', 1, 0);
    final x = _unit(w, 'blue', 4, 4);
    startTurnBasedGame(w, ['red', 'blue']);
    selectInBox(w, 0, 0, 1, 0);
    expect(commandSelected(w, 3, 3), 2);
    expect(w.storeOf<OrderQueue>().get(a)!.orders.single, isA<MoveOrder>());
    expect(commandSelected(w, 4, 4), 2);
    final q = w.storeOf<OrderQueue>().get(b)!.orders;
    expect(q.single, isA<AttackOrder>());
    expect((q.single as AttackOrder).target, x);
    expect(commandSelected(w, 2, 2, replace: false), 2);
    expect(w.storeOf<OrderQueue>().get(b)!.orders, hasLength(2));
  });

  test('selection drops after the turn passes: stale units are not commanded', () {
    final w = _world();
    _unit(w, 'red', 0, 0);
    _unit(w, 'blue', 5, 5);
    startTurnBasedGame(w, ['red', 'blue']);
    selectAtCell(w, 0, 0);
    endTurn(w);
    expect(commandSelected(w, 1, 1), 0);
    clearSelection(w);
    expect(selectedEntities(w), isEmpty);
  });

  test('GridToWorldSystem centers entities in their cell', () {
    final w = _world();
    final a = _unit(w, 'red', 2, 3);
    w.storeOf<Position>().set(a, Position(0, 0));
    w.addSystem(GridToWorldSystem(32));
    w.step(0.1);
    final p = w.storeOf<Position>().get(a)!;
    expect((p.x, p.y), (80.0, 112.0));
  });
}
