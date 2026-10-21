import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world({Map<String, TurnAI>? ai}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  w.addSystem(OrderSystem(approachTargets: true));
  w.addSystem(AITurnSystem(ai ?? {'blue': AggressiveAI()}));
  installCombat(w);
  return w;
}

EntityId _unit(
  World w,
  String team,
  int c,
  int r, {
  int ap = 3,
  int hp = 10,
  int atk = 3,
}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: hp, attack: atk));
  return e;
}

void main() {
  test(
    'AI plans on its turn, orders run, then the turn ends back to the human team',
    () {
      final w = _world();
      final human = _unit(w, 'red', 0, 0);
      final bot = _unit(w, 'blue', 2, 0, hp: 10);
      startTurnBasedGame(w, ['red', 'blue']);
      expect(turnStateOf(w)!.activeTeam, 'red');
      endTurn(w);
      expect(turnStateOf(w)!.activeTeam, 'blue');

      w.step(0.1);
      expect(
        w.storeOf<OrderQueue>().get(bot)!.orders.single,
        isA<AttackOrder>(),
      );
      w.step(0.1);
      expect(w.storeOf<UnitStats>().get(human)!.hp, 7);
      w.step(0.1);
      expect(turnStateOf(w)!.activeTeam, 'red');
      expect(turnStateOf(w)!.round, 2);
    },
  );

  test('AI with nothing in sight holds and still ends its turn', () {
    final w = _world();
    final fog = w.spawn();
    w.storeOf<FogOfWar>().set(fog, FogOfWar(10, 10));
    _unit(w, 'red', 0, 0);
    _unit(w, 'blue', 9, 9);
    startTurnBasedGame(w, ['red', 'blue']);
    endTurn(w);
    w.step(0.1);
    w.step(0.1);
    expect(turnStateOf(w)!.activeTeam, 'red');
  });

  test('AI cannot attack an enemy hidden by fog', () {
    final w = _world();
    final fog = w.spawn();
    w.storeOf<FogOfWar>().set(fog, FogOfWar(10, 10));
    _unit(w, 'red', 0, 0);
    final bot = _unit(w, 'blue', 1, 0);
    w.storeOf<Vision>().set(bot, Vision(0));
    w.addSystem(VisionSystem());
    startTurnBasedGame(w, ['red', 'blue']);
    endTurn(w);
    w.step(0.1);
    expect(w.storeOf<OrderQueue>().get(bot)?.orders ?? [], isEmpty);
  });

  test('human-controlled teams are left alone', () {
    final w = _world();
    _unit(w, 'red', 0, 0);
    _unit(w, 'blue', 3, 0);
    startTurnBasedGame(w, ['red', 'blue']);
    for (var i = 0; i < 5; i++) {
      w.step(0.1);
    }
    expect(turnStateOf(w)!.activeTeam, 'red');
  });

  test(
    'a unit that cannot afford its order does not stall the turn forever',
    () {
      final w = _world();
      _unit(w, 'red', 0, 0, hp: 50);
      final bot = _unit(w, 'blue', 9, 0, ap: 2);
      startTurnBasedGame(w, ['red', 'blue']);
      endTurn(w);
      for (var i = 0; i < 4; i++) {
        w.step(0.1);
      }
      expect(turnStateOf(w)!.activeTeam, 'red');
      expect(w.storeOf<OrderQueue>().get(bot)!.orders, isNotEmpty);
    },
  );

  test('AI replans each round (second round still acts)', () {
    final w = _world();
    final human = _unit(w, 'red', 0, 0, hp: 100);
    _unit(w, 'blue', 1, 0);
    startTurnBasedGame(w, ['red', 'blue']);
    for (var round = 0; round < 2; round++) {
      endTurn(w);
      for (var i = 0; i < 4; i++) {
        w.step(0.1);
      }
    }
    expect(w.storeOf<UnitStats>().get(human)!.hp, 94);
  });

  test('AI does nothing after victory', () {
    final w = _world();
    _unit(w, 'red', 0, 0);
    _unit(w, 'blue', 1, 0);
    startTurnBasedGame(w, ['red', 'blue']);
    endTurn(w);
    turnStateOf(w)!.winner = 'red';
    w.step(0.1);
    w.step(0.1);
    expect(turnStateOf(w)!.activeTeam, 'blue');
  });
}
