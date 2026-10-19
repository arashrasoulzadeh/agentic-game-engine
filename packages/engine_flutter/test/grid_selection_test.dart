import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  return w;
}

EntityId _unit(World w, String team, int c, int r) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(5, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<Position>().set(e, Position((c + 0.5) * 32, (r + 0.5) * 32));
  return e;
}

void main() {
  test(
    'tap selects own unit, then commands a move, ignores empty with no selection',
    () {
      final w = _world();
      final a = _unit(w, 'red', 1, 1);
      startTurnBasedGame(w, ['red', 'blue']);
      final c = GridTapController(32);
      expect(c.handleTap(w, const Offset(200, 200)), GridTapResult.ignored);
      expect(c.handleTap(w, const Offset(48, 48)), GridTapResult.selected);
      expect(c.handleTap(w, const Offset(130, 40)), GridTapResult.commanded);
      final order = w.storeOf<OrderQueue>().get(a)!.orders.single as MoveOrder;
      expect((order.col, order.row), (4, 1));
    },
  );

  test('origin offset shifts the cell mapping', () {
    final c = GridTapController(32, originX: 100, originY: 50);
    expect((c.colOf(100), c.rowOf(50)), (0, 0));
    expect((c.colOf(99), c.rowOf(49)), (-1, -1));
  });

  test('drag box-selects', () {
    final w = _world();
    _unit(w, 'red', 0, 0);
    _unit(w, 'red', 1, 1);
    startTurnBasedGame(w, ['red']);
    expect(
      GridTapController(
        32,
      ).handleDrag(w, const Offset(60, 60), const Offset(2, 2)),
      2,
    );
  });

  test(
    'markers are created per selection, follow the unit, and are removed on deselect',
    () {
      final w = _world();
      final a = _unit(w, 'red', 2, 3);
      startTurnBasedGame(w, ['red']);
      w.addSystem(SelectionMarkerSystem(32));
      w.storeOf<Selected>().set(a, const Selected());
      w.step(0.1);
      w.step(0.1);
      final markers = w.storeOf<SelectionMarker>();
      expect(markers.length, 1);
      final m = markers.entityAt(0);
      final bar = w.storeOf<HudBar>().get(m)!;
      expect(bar.screenSpace, isFalse);
      final mp = w.storeOf<Position>().get(m)!;
      expect((mp.x, mp.y), (64.0, 3 * 32.0 + 32 - 4));

      w.storeOf<Position>().get(a)!.x += 32;
      w.step(0.1);
      expect(w.storeOf<Position>().get(m)!.x, 96.0);

      clearSelection(w);
      w.step(0.1);
      expect(markers.length, 0);
      expect(w.storeOf<HudBar>().length, 0);
    },
  );

  test('marker for a destroyed unit is cleaned up', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0);
    startTurnBasedGame(w, ['red']);
    w.addSystem(SelectionMarkerSystem(32));
    w.storeOf<Selected>().set(a, const Selected());
    w.step(0.1);
    w.destroy(a);
    w.step(0.1);
    expect(w.storeOf<SelectionMarker>().length, 0);
  });
}
