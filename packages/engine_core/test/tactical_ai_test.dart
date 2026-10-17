import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() => GridNavigator(cols: 10, rows: 10, terrainCost: (c, r) => 1);

World _world({bool fog = false}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  if (fog) {
    w.storeOf<FogOfWar>().set(w.spawn(), FogOfWar(10, 10));
    w.addSystem(VisionSystem());
  }
  w.addSystem(OrderSystem.withNavigator(_nav()));
  return w;
}

EntityId _unit(World w, String team, int c, int r, {int hp = 10, int maxHp = 10, int ap = 3, int? vision}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: maxHp, hp: hp));
  if (vision != null) w.storeOf<Vision>().set(e, Vision(vision));
  return e;
}

Order _first(World w, EntityId e) => w.storeOf<OrderQueue>().get(e)!.orders.first;

void _play(World w, TurnAI ai, {String team = 'blue'}) {
  startTurnBasedGame(w, ['red', 'blue']);
  endTurn(w);
  ai.playTurn(w, team);
}

void main() {
  group('focus fire', () {
    test('every unit targets the visible enemy with the fewest hit points', () {
      final w = _world();
      _unit(w, 'red', 0, 0, hp: 9);
      final weak = _unit(w, 'red', 5, 5, hp: 2);
      final a = _unit(w, 'blue', 1, 1);
      final b = _unit(w, 'blue', 9, 9);
      _play(w, TacticalAI());
      expect((_first(w, a) as AttackOrder).target, weak);
      expect((_first(w, b) as AttackOrder).target, weak);
    });

    test('with focus fire off each unit picks its own nearest enemy', () {
      final w = _world();
      final nearA = _unit(w, 'red', 0, 0, hp: 9);
      final nearB = _unit(w, 'red', 9, 9, hp: 9);
      final a = _unit(w, 'blue', 1, 1);
      final b = _unit(w, 'blue', 8, 8);
      _play(w, TacticalAI(focusFire: false));
      expect((_first(w, a) as AttackOrder).target, nearA);
      expect((_first(w, b) as AttackOrder).target, nearB);
    });

    test('equal hit points break the tie toward the target nearest the team', () {
      final w = _world();
      final close = _unit(w, 'red', 3, 3);
      _unit(w, 'red', 9, 9);
      final a = _unit(w, 'blue', 2, 2);
      _play(w, TacticalAI());
      expect((_first(w, a) as AttackOrder).target, close);
    });
  });

  group('retreat', () {
    test('a badly hurt unit runs to the reachable cell farthest from the enemy', () {
      final w = _world();
      _unit(w, 'red', 4, 4);
      final hurt = _unit(w, 'blue', 5, 4, hp: 1);
      _play(w, TacticalAI(navigator: _nav()));
      final order = _first(w, hurt) as MoveOrder;
      expect(order.col, 8, reason: '3 points of movement straight away from the enemy at (4,4)');
      expect(w.storeOf<OrderQueue>().get(hurt)!.orders, hasLength(1));
    });

    test('a healthy unit still attacks', () {
      final w = _world();
      _unit(w, 'red', 4, 4);
      final fine = _unit(w, 'blue', 5, 4, hp: 9);
      _play(w, TacticalAI(navigator: _nav()));
      expect(_first(w, fine), isA<AttackOrder>());
    });

    test('without a navigator, or with retreat off, a hurt unit fights on', () {
      for (final ai in [TacticalAI(), TacticalAI(navigator: _nav(), retreatBelow: 0)]) {
        final w = _world();
        _unit(w, 'red', 4, 4);
        final hurt = _unit(w, 'blue', 5, 4, hp: 1);
        _play(w, ai);
        expect(_first(w, hurt), isA<AttackOrder>());
      }
    });

    test('a cornered unit with nowhere safer to go attacks instead', () {
      final w = _world();
      _unit(w, 'red', 1, 0);
      final cornered = _unit(w, 'blue', 0, 0, hp: 1, ap: 1);
      _unit(w, 'blue', 0, 1, ap: 0);
      _play(w, TacticalAI(navigator: _nav()));
      expect(_first(w, cornered), isA<AttackOrder>());
    });
  });

  group('explore', () {
    test('with nothing visible, units claim different unexplored cells', () {
      final w = _world(fog: true);
      _unit(w, 'red', 9, 9);
      final a = _unit(w, 'blue', 0, 0, vision: 1);
      final b = _unit(w, 'blue', 0, 1, vision: 1);
      startTurnBasedGame(w, ['red', 'blue']);
      w.step(0.1);
      endTurn(w);
      TacticalAI(navigator: _nav()).playTurn(w, 'blue');
      final oa = _first(w, a) as MoveOrder, ob = _first(w, b) as MoveOrder;
      expect((oa.col, oa.row), isNot((ob.col, ob.row)));
      final fog = fogOf(w)!;
      expect(fog.isExplored('blue', oa.col, oa.row), isFalse);
      expect(fog.isExplored('blue', ob.col, ob.row), isFalse);
    });

    test('exploring happens only with a navigator and when enabled', () {
      List<Order> orders(TacticalAI ai) {
        final w = _world(fog: true);
        _unit(w, 'red', 9, 9);
        final u = _unit(w, 'blue', 0, 0, vision: 1);
        startTurnBasedGame(w, ['red', 'blue']);
        w.step(0.1);
        endTurn(w);
        ai.playTurn(w, 'blue');
        return w.storeOf<OrderQueue>().get(u)?.orders ?? const [];
      }

      expect(orders(TacticalAI(navigator: _nav())).whereType<MoveOrder>(), hasLength(1));
      expect(orders(TacticalAI()), isEmpty, reason: 'no navigator');
      expect(orders(TacticalAI(navigator: _nav(), explore: false)), isEmpty, reason: 'disabled');
    });

    test('with no fog in the game there is nothing to explore', () {
      final w = _world();
      _unit(w, 'red', 9, 9);
      final u = _unit(w, 'blue', 0, 0);
      _play(w, TacticalAI(navigator: _nav()));
      expect(_first(w, u), isA<AttackOrder>(), reason: 'without fog the enemy is always visible');
    });
  });

  group('hold', () {
    test('defendWhenIdle braces idle units; off by default', () {
      for (final defend in [true, false]) {
        final w = _world(fog: true);
        _unit(w, 'red', 9, 9);
        final u = _unit(w, 'blue', 0, 0, vision: 0);
        startTurnBasedGame(w, ['red', 'blue']);
        w.step(0.1);
        endTurn(w);
        TacticalAI(defendWhenIdle: defend).playTurn(w, 'blue');
        final queue = w.storeOf<OrderQueue>().get(u)?.orders ?? const [];
        expect(queue.any((o) => o is DefendOrder), defend);
      }
    });
  });

  test('previous orders are cleared and spent units are skipped', () {
    final w = _world();
    _unit(w, 'red', 0, 0);
    final a = _unit(w, 'blue', 1, 0);
    final spent = _unit(w, 'blue', 2, 0);
    startTurnBasedGame(w, ['red', 'blue']);
    endTurn(w);
    w.storeOf<ActionPoints>().get(spent)!.current = 0;
    w.storeOf<OrderQueue>().set(a, OrderQueue([const MoveOrder(9, 9), const MoveOrder(8, 8)]));
    TacticalAI().playTurn(w, 'blue');
    expect(w.storeOf<OrderQueue>().get(a)!.orders.single, isA<AttackOrder>());
    expect(w.storeOf<OrderQueue>().get(spent)?.orders ?? const [], isEmpty);
  });

  test('it only targets what its team can see', () {
    final w = _world(fog: true);
    _unit(w, 'red', 9, 9);
    final u = _unit(w, 'blue', 0, 0, vision: 2);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    endTurn(w);
    TacticalAI().playTurn(w, 'blue');
    final queue = w.storeOf<OrderQueue>().get(u)?.orders ?? const [];
    expect(queue.whereType<AttackOrder>(), isEmpty);
  });

  test('plugs into AITurnSystem and finishes a whole game', () {
    final w = _world();
    w.addSystem(AITurnSystem({'blue': TacticalAI(navigator: _nav())}));
    w.addSystem(WinConditionSystem());
    installCombat(w);
    final hero = _unit(w, 'red', 0, 0, hp: 40);
    w.storeOf<UnitStats>().get(hero)!.attack = 6;
    _unit(w, 'blue', 5, 0, hp: 10);
    startTurnBasedGame(w, ['red', 'blue']);
    for (var round = 0; round < 12 && turnStateOf(w)!.winner == null; round++) {
      final enemies = [
        for (var i = 0; i < w.storeOf<Team>().length; i++)
          if (w.storeOf<Team>().denseAt(i).id == 'blue') w.storeOf<Team>().entityAt(i),
      ];
      if (enemies.isNotEmpty) submitOrder(w, hero, AttackOrder(enemies.first));
      w.step(0.1);
      endTurn(w);
      for (var i = 0; i < 5; i++) {
        w.step(0.1);
      }
    }
    expect(turnStateOf(w)!.winner, 'red');
  });
}
