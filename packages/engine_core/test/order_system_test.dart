import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  w.addSystem(OrderSystem());
  return w;
}

EntityId _unit(World w, String team, int col, int row, int ap) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(col, row));
  return e;
}

void main() {
  test('order JSON round trips and rejects unknown types', () {
    final q = OrderQueue([const MoveOrder(2, 3), const AttackOrder(7)]);
    final back = OrderQueue.fromJson(q.toJson());
    expect((back.orders[0] as MoveOrder).row, 3);
    expect((back.orders[1] as AttackOrder).target, 7);
    expect(() => Order.fromJson({'type': 'nope'}), throwsFormatException);
  });

  test('submitOrder rejects the inactive team', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0, 3);
    final b = _unit(w, 'blue', 5, 5, 3);
    startTurnBasedGame(w, ['red', 'blue']);
    expect(submitOrder(w, b, const MoveOrder(5, 4)), isFalse);
    expect(submitOrder(w, a, const MoveOrder(1, 0)), isTrue);
  });

  test('move spends one AP per cell and resumes next turn when short', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0, 2);
    _unit(w, 'blue', 9, 9, 2);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, a, const MoveOrder(3, 0));
    w.step(0.1);
    var p = w.storeOf<GridPosition>().get(a)!;
    expect([p.col, p.row], [2, 0]);
    expect(w.storeOf<ActionPoints>().get(a)!.current, 0);
    expect(w.storeOf<OrderQueue>().get(a)!.orders, hasLength(1));

    endTurn(w);
    endTurn(w);
    w.step(0.1);
    p = w.storeOf<GridPosition>().get(a)!;
    expect([p.col, p.row], [3, 0]);
    expect(w.storeOf<OrderQueue>().get(a)!.orders, isEmpty);
  });

  test('move into a blocked straight line fails with blocked', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0, 3);
    _unit(w, 'blue', 1, 0, 3);
    startTurnBasedGame(w, ['red', 'blue']);
    final failed = <OrderFailedEvent>[];
    w.events.on<OrderFailedEvent>(failed.add);
    submitOrder(w, a, const MoveOrder(2, 0));
    w.step(0.1);
    expect(failed.single.reason, OrderFailure.blocked);
    expect(w.storeOf<OrderQueue>().get(a)!.orders, isEmpty);
  });

  test('move routes around an obstacle on the other axis', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0, 5);
    _unit(w, 'blue', 1, 0, 3);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, a, const MoveOrder(1, 1));
    w.step(0.1);
    final p = w.storeOf<GridPosition>().get(a)!;
    expect([p.col, p.row], [1, 1]);
  });

  test('attack resolves in range, fails out of range', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0, 3);
    final near = _unit(w, 'blue', 1, 1, 3);
    final far = _unit(w, 'blue', 5, 5, 3);
    startTurnBasedGame(w, ['red', 'blue']);
    final hits = <AttackResolvedEvent>[];
    final failed = <OrderFailedEvent>[];
    w.events.on<AttackResolvedEvent>(hits.add);
    w.events.on<OrderFailedEvent>(failed.add);
    submitOrder(w, a, AttackOrder(far));
    submitOrder(w, a, AttackOrder(near));
    w.step(0.1);
    expect(failed.single.reason, OrderFailure.outOfRange);
    expect(hits.single.target, near);
    expect(w.storeOf<ActionPoints>().get(a)!.current, 2);
  });

  test('attack on a destroyed target is invalid', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0, 3);
    final t = _unit(w, 'blue', 1, 0, 3);
    startTurnBasedGame(w, ['red', 'blue']);
    final failed = <OrderFailedEvent>[];
    w.events.on<OrderFailedEvent>(failed.add);
    submitOrder(w, a, AttackOrder(t));
    w.destroy(t);
    w.step(0.1);
    expect(failed.single.reason, OrderFailure.invalidTarget);
  });

  test('orders of the inactive team do not execute', () {
    final w = _world();
    _unit(w, 'red', 0, 0, 3);
    final b = _unit(w, 'blue', 5, 5, 3);
    startTurnBasedGame(w, ['red', 'blue']);
    w.storeOf<OrderQueue>().set(b, OrderQueue([const MoveOrder(5, 6)]));
    w.step(0.1);
    expect(w.storeOf<GridPosition>().get(b)!.row, 5);
  });
}
