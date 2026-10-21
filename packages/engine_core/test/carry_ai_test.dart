import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() =>
    GridNavigator(cols: 20, rows: 20, terrainCost: (c, r) => 1);

World _world() {
  final w = World(width: 20, height: 20);
  registerCoreComponents(w);
  w.addSystem(OrderSystem.withNavigator(_nav()));
  installCombat(w);
  return w;
}

EntityId _unit(World w, String team, int c, int r, {int ap = 6, int hp = 10}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: hp, attack: 3));
  return e;
}

EntityId _flag(World w, String home, int c, int r, {EntityId? carrier}) {
  final e = w.spawn();
  w.storeOf<Flag>().set(e, Flag('$home flag', home, c, r, carrier: carrier));
  return e;
}

void _zone(World w, String team, int c, int r) =>
    w.storeOf<DeliveryZone>().set(w.spawn(), DeliveryZone(team, c, r));

Order _first(World w, EntityId e) =>
    w.storeOf<OrderQueue>().get(e)!.orders.first;

void _play(World w) {
  startTurnBasedGame(w, ['red', 'blue']);
  endTurn(w);
  ObjectiveAI(navigator: _nav()).playTurn(w, 'blue');
}

void main() {
  test('a carrier runs for its own delivery zone', () {
    final w = _world();
    final carrier = _unit(w, 'blue', 10, 10);
    _flag(w, 'red', 10, 10, carrier: carrier);
    _zone(w, 'blue', 2, 17);
    _unit(w, 'red', 18, 1);
    _play(w);
    final m = _first(w, carrier) as MoveOrder;
    expect((m.col, m.row), (2, 17));
  });

  test('only the unit nearest to a loose enemy flag goes for it', () {
    final w = _world();
    _flag(w, 'red', 15, 15);
    final near = _unit(w, 'blue', 12, 12);
    final far = _unit(w, 'blue', 1, 1);
    _unit(w, 'red', 0, 19);
    _play(w);
    final grab = _first(w, near) as MoveOrder;
    expect((grab.col, grab.row), (15, 15));
    final other = w.storeOf<OrderQueue>().get(far)?.orders ?? const [];
    expect(
      other.whereType<MoveOrder>().where((m) => m.col == 15 && m.row == 15),
      isEmpty,
      reason: 'one unit per flag - the other does something else',
    );
  });

  test('two loose flags are fetched by two different units', () {
    final w = _world();
    _flag(w, 'red', 15, 15);
    _flag(w, 'red', 3, 15);
    final a = _unit(w, 'blue', 14, 14);
    final b = _unit(w, 'blue', 4, 14);
    _unit(w, 'red', 0, 0);
    _play(w);
    final ga = _first(w, a) as MoveOrder, gb = _first(w, b) as MoveOrder;
    expect({(ga.col, ga.row), (gb.col, gb.row)}, {(15, 15), (3, 15)});
  });

  test('when an enemy carries our flag, nearby units attack the carrier', () {
    final w = _world();
    final thief = _unit(w, 'red', 10, 10);
    _flag(w, 'blue', 10, 10, carrier: thief);
    final guard = _unit(w, 'blue', 8, 8);
    _unit(w, 'red', 19, 19);
    _play(w);
    expect((_first(w, guard) as AttackOrder).target, thief);
  });

  test('the Vip retreats from nearby enemies instead of fighting', () {
    final w = _world();
    final king = _unit(w, 'blue', 10, 10);
    w.storeOf<Vip>().set(king, const Vip());
    final foe = _unit(w, 'red', 12, 10);
    _play(w);
    final m = _first(w, king) as MoveOrder;
    final from = GridPosition(10, 10),
        foePos = w.storeOf<GridPosition>().get(foe)!;
    expect(
      GridPosition(m.col, m.row).chebyshev(foePos),
      greaterThan(from.chebyshev(foePos)),
    );
  });

  test(
    'a Vip never goes to fetch a flag; a far-away enemy does not scare it',
    () {
      final w = _world();
      final king = _unit(w, 'blue', 2, 2);
      w.storeOf<Vip>().set(king, const Vip());
      _flag(w, 'red', 3, 3);
      final soldier = _unit(w, 'blue', 18, 18);
      _unit(w, 'red', 18, 0);
      _play(w);
      final kingOrders = w.storeOf<OrderQueue>().get(king)?.orders ?? const [];
      expect(
        kingOrders.whereType<MoveOrder>().where(
          (m) => m.col == 3 && m.row == 3,
        ),
        isEmpty,
      );
      expect(
        _first(w, soldier),
        isA<MoveOrder>(),
        reason: 'the soldier takes the flag job instead',
      );
    },
  );

  test('a full capture: the AI fetches the flag, brings it home and wins', () {
    final w = _world();
    w.addSystem(AITurnSystem({'blue': ObjectiveAI(navigator: _nav())}));
    w.addSystem(WinConditionSystem());
    _flag(w, 'red', 12, 4);
    _zone(w, 'blue', 2, 4);
    w.storeOf<FlagRules>().set(w.spawn(), FlagRules(capturesToWin: 1));
    _unit(w, 'blue', 3, 4, ap: 6);
    _unit(w, 'red', 18, 18);
    startTurnBasedGame(w, ['red', 'blue']);
    for (var round = 0; round < 15 && turnStateOf(w)!.winner == null; round++) {
      w.step(0.1);
      endTurn(w);
      for (var i = 0; i < 5; i++) {
        w.step(0.1);
      }
    }
    expect(turnStateOf(w)!.winner, 'blue');
  });
}
