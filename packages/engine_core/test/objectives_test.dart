import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() => GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1);

World _world({int? holdToWin}) {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  w.addSystem(OrderSystem.withNavigator(_nav()));
  installCombat(w);
  if (holdToWin != null) {
    w.storeOf<ObjectiveRules>().set(w.spawn(), ObjectiveRules(holdTurnsToWin: holdToWin));
  }
  return w;
}

EntityId _unit(World w, String team, int c, int r, {int ap = 4, int hp = 20, int atk = 3}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: hp, attack: atk));
  return e;
}

EntityId _flag(World w, String id, int c, int r, {String? owner}) {
  final e = w.spawn();
  w.storeOf<Objective>().set(e, Objective(id, c, r, owner: owner));
  return e;
}

Objective _obj(World w, EntityId e) => w.storeOf<Objective>().get(e)!;

void main() {
  group('capture', () {
    test('standing on a neutral objective at your turn start captures it and announces it', () {
      final w = _world();
      final flag = _flag(w, 'flag', 3, 3);
      _unit(w, 'red', 3, 3);
      _unit(w, 'blue', 9, 9);
      final events = <ObjectiveCapturedEvent>[];
      w.events.on<ObjectiveCapturedEvent>(events.add);
      startTurnBasedGame(w, ['red', 'blue']);
      w.events.flush();
      expect(_obj(w, flag).owner, 'red');
      expect(events.single.team, 'red');
      expect(events.single.previousOwner, isNull);
    });

    test('an enemy standing there takes it on their turn; ownership persists otherwise', () {
      final w = _world();
      final flag = _flag(w, 'flag', 3, 3, owner: 'red');
      final intruder = _unit(w, 'blue', 3, 3);
      _unit(w, 'red', 9, 9);
      final events = <ObjectiveCapturedEvent>[];
      w.events.on<ObjectiveCapturedEvent>(events.add);
      startTurnBasedGame(w, ['red', 'blue']);
      expect(_obj(w, flag).owner, 'red', reason: 'red has nobody on it but still owns it');
      endTurn(w);
      w.events.flush();
      expect(_obj(w, flag).owner, 'blue');
      expect(events.single.previousOwner, 'red');
      expect(w.entities.isAlive(intruder), isTrue);
    });

    test('capture happens as the turn begins, before a queued order can walk the unit away', () {
      final w = _world();
      final flag = _flag(w, 'flag', 3, 3);
      final u = _unit(w, 'blue', 3, 3);
      _unit(w, 'red', 9, 9);
      w.storeOf<OrderQueue>().set(u, OrderQueue([const MoveOrder(8, 8)]));
      startTurnBasedGame(w, ['red', 'blue']);
      expect(_obj(w, flag).owner, isNull);
      endTurn(w); // blue's turn begins; no step has run yet
      expect(_obj(w, flag).owner, 'blue');
    });

    test('merely being nearby, or capturing what you already own, does nothing', () {
      final w = _world();
      final flag = _flag(w, 'flag', 3, 3);
      _unit(w, 'red', 3, 4);
      _unit(w, 'blue', 9, 9);
      final events = <ObjectiveCapturedEvent>[];
      w.events.on<ObjectiveCapturedEvent>(events.add);
      startTurnBasedGame(w, ['red', 'blue']);
      w.events.flush();
      expect(_obj(w, flag).owner, isNull);
      expect(events, isEmpty);
    });

    test('Objective and ObjectiveRules round-trip JSON', () {
      final o = Objective.fromJson(Objective('x', 1, 2, owner: 'red').toJson());
      expect((o.id, o.col, o.row, o.owner), ('x', 1, 2, 'red'));
      expect(Objective.fromJson(Objective('y', 0, 0).toJson()).owner, isNull);
      final r = ObjectiveRules.fromJson(ObjectiveRules(holdTurnsToWin: 3, holds: {'red': 2}).toJson());
      expect((r.holdTurnsToWin, r.holds['red']), (3, 2));
    });

    test('objectivesToTake lists neutral and enemy-held points', () {
      final w = _world();
      _flag(w, 'mine', 0, 0, owner: 'red');
      _flag(w, 'theirs', 1, 0, owner: 'blue');
      _flag(w, 'free', 2, 0);
      expect(objectivesToTake(w, 'red').map((t) => t.$2.id).toSet(), {'theirs', 'free'});
    });
  });

  group('hold to win', () {
    test('owning every objective for N consecutive own turns wins; losing one resets', () {
      final w = _world(holdToWin: 2);
      _flag(w, 'a', 1, 1);
      _flag(w, 'b', 2, 1);
      final u1 = _unit(w, 'red', 1, 1);
      _unit(w, 'red', 2, 1);
      _unit(w, 'blue', 9, 9);
      final victories = <VictoryEvent>[];
      w.events.on<VictoryEvent>(victories.add);
      startTurnBasedGame(w, ['red', 'blue']); // red turn 1: owns all -> hold 1
      expect(turnStateOf(w)!.winner, isNull);
      expect(w.storeOf<ObjectiveRules>().denseAt(0).holds['red'], 1);

      endTurn(w);
      endTurn(w); // red turn 2: hold 2 -> win
      w.events.flush();
      expect(turnStateOf(w)!.winner, 'red');
      expect(victories.single.team, 'red');
      expect(u1, isNotNull);
    });

    test('losing an objective in between resets the count', () {
      final w = _world(holdToWin: 2);
      final a = _flag(w, 'a', 1, 1);
      _flag(w, 'b', 2, 1);
      final u1 = _unit(w, 'red', 1, 1);
      _unit(w, 'red', 2, 1);
      _unit(w, 'blue', 9, 9);
      startTurnBasedGame(w, ['red', 'blue']);
      expect(w.storeOf<ObjectiveRules>().denseAt(0).holds['red'], 1);
      _obj(w, a).owner = 'blue'; // taken from them
      w.storeOf<GridPosition>().get(u1)!.col = 5; // and red's unit is not on it to retake
      endTurn(w);
      endTurn(w);
      expect(w.storeOf<ObjectiveRules>().denseAt(0).holds['red'], 0);
      expect(turnStateOf(w)!.winner, isNull);
    });

    test('without ObjectiveRules, holding everything does not end the game', () {
      final w = _world();
      _flag(w, 'a', 1, 1);
      _unit(w, 'red', 1, 1);
      _unit(w, 'blue', 9, 9);
      startTurnBasedGame(w, ['red', 'blue']);
      for (var i = 0; i < 6; i++) {
        endTurn(w);
      }
      expect(turnStateOf(w)!.winner, isNull);
    });
  });

  group('ObjectiveAI', () {
    Order first(World w, EntityId e) => w.storeOf<OrderQueue>().get(e)!.orders.first;

    void play(World w, TurnAI ai) {
      startTurnBasedGame(w, ['red', 'blue']);
      endTurn(w);
      ai.playTurn(w, 'blue');
    }

    test('with no enemy near, units march to the nearest objective they do not own', () {
      final w = _world();
      _flag(w, 'near', 8, 8);
      _flag(w, 'far', 0, 0);
      final u = _unit(w, 'blue', 10, 10);
      _unit(w, 'red', 0, 11);
      play(w, ObjectiveAI(navigator: _nav()));
      final m = first(w, u) as MoveOrder;
      expect((m.col, m.row), (8, 8));
    });

    test('units spread over different objectives while some are unclaimed', () {
      final w = _world();
      _flag(w, 'a', 10, 0);
      _flag(w, 'b', 0, 10);
      final u1 = _unit(w, 'blue', 9, 1);
      final u2 = _unit(w, 'blue', 9, 2);
      _unit(w, 'red', 5, 11);
      play(w, ObjectiveAI(navigator: _nav()));
      final g1 = first(w, u1) as MoveOrder, g2 = first(w, u2) as MoveOrder;
      expect((g1.col, g1.row), isNot((g2.col, g2.row)));
    });

    test('a garrison on an owned objective braces when an enemy approaches but is not yet in range', () {
      final w = _world();
      _flag(w, 'keep', 6, 6, owner: 'blue');
      _flag(w, 'other', 0, 0);
      final garrison = _unit(w, 'blue', 6, 6);
      _unit(w, 'red', 6, 11);
      play(w, ObjectiveAI(navigator: _nav(), engageRange: 3, holdRadius: 6));
      expect(first(w, garrison), isA<DefendOrder>());
    });

    test('a garrison attacks an enemy within engage range instead of leaving', () {
      final w = _world();
      _flag(w, 'keep', 6, 6, owner: 'blue');
      final garrison = _unit(w, 'blue', 6, 6);
      final foe = _unit(w, 'red', 6, 8);
      play(w, ObjectiveAI(navigator: _nav()));
      expect((first(w, garrison) as AttackOrder).target, foe);
    });

    test('a free unit with an enemy in engage range fights it rather than marching', () {
      final w = _world();
      _flag(w, 'far', 0, 0);
      final u = _unit(w, 'blue', 8, 8);
      final foe = _unit(w, 'red', 8, 10);
      play(w, ObjectiveAI(navigator: _nav()));
      expect((first(w, u) as AttackOrder).target, foe);
    });

    test('a garrison with no enemy near is free to leave for another objective', () {
      final w = _world();
      _flag(w, 'keep', 6, 6, owner: 'blue');
      _flag(w, 'other', 11, 0);
      final u = _unit(w, 'blue', 6, 6);
      _unit(w, 'red', 0, 11);
      play(w, ObjectiveAI(navigator: _nav(), holdRadius: 3));
      expect(first(w, u), isA<MoveOrder>());
    });

    test('all objectives owned and no enemies at all: it does nothing', () {
      final w = _world();
      _flag(w, 'keep', 6, 6, owner: 'blue');
      final u = _unit(w, 'blue', 6, 6);
      startTurnBasedGame(w, ['red', 'blue']);
      endTurn(w);
      ObjectiveAI(navigator: _nav()).playTurn(w, 'blue');
      expect(w.storeOf<OrderQueue>().get(u)?.orders ?? const [], isEmpty);
    });

    test('with nothing left to capture it hunts the visible enemy', () {
      final w = _world();
      _flag(w, 'keep', 6, 6, owner: 'blue');
      final u = _unit(w, 'blue', 2, 2);
      final foe = _unit(w, 'red', 11, 11);
      play(w, ObjectiveAI(navigator: _nav(), engageRange: 3));
      expect((first(w, u) as AttackOrder).target, foe);
    });

    test('plays a full capture game through AITurnSystem', () {
      final w = _world(holdToWin: 2);
      w.addSystem(AITurnSystem({'blue': ObjectiveAI(navigator: _nav())}));
      _flag(w, 'hill', 6, 6);
      _unit(w, 'blue', 6, 9, ap: 6);
      _unit(w, 'red', 0, 0);
      startTurnBasedGame(w, ['red', 'blue']);
      for (var round = 0; round < 12 && turnStateOf(w)!.winner == null; round++) {
        w.step(0.1);
        endTurn(w);
        for (var i = 0; i < 5; i++) {
          w.step(0.1);
        }
      }
      expect(turnStateOf(w)!.winner, 'blue');
    });
  });
}
