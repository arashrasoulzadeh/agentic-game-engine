import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  w.addSystem(OrderSystem());
  w.addSystem(WinConditionSystem());
  installCombat(w);
  return w;
}

EntityId _unit(
  World w,
  String team,
  int c,
  int r, {
  int hp = 5,
  int atk = 3,
  int def = 0,
}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(4, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(
    e,
    UnitStats(maxHp: hp, attack: atk, defense: def),
  );
  return e;
}

void main() {
  test('damage is attack minus defense, minimum 1', () {
    expect(
      damageFor(
        UnitStats(maxHp: 1, attack: 5),
        UnitStats(maxHp: 1, defense: 2),
      ),
      3,
    );
    expect(
      damageFor(
        UnitStats(maxHp: 1, attack: 1),
        UnitStats(maxHp: 1, defense: 9),
      ),
      1,
    );
  });

  test('attack order damages the target and emits events', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0);
    final b = _unit(w, 'blue', 1, 0, hp: 10, def: 1);
    startTurnBasedGame(w, ['red', 'blue']);
    final dmg = <UnitDamagedEvent>[];
    w.events.on<UnitDamagedEvent>(dmg.add);
    submitOrder(w, a, AttackOrder(b));
    w.step(0.1);
    expect(w.storeOf<UnitStats>().get(b)!.hp, 8);
    expect(dmg.single.amount, 2);
  });

  test('friendly fire is refused', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0);
    final b = _unit(w, 'red', 1, 0);
    _unit(w, 'blue', 5, 5);
    startTurnBasedGame(w, ['red', 'blue']);
    final failed = <OrderFailedEvent>[];
    w.events.on<OrderFailedEvent>(failed.add);
    submitOrder(w, a, AttackOrder(b));
    w.step(0.1);
    expect(failed.single.reason, OrderFailure.invalidTarget);
    expect(w.storeOf<UnitStats>().get(b)!.hp, 5);
  });

  test(
    'killing the last enemy unit eliminates the team and declares victory',
    () {
      final w = _world();
      final a = _unit(w, 'red', 0, 0);
      final b = _unit(w, 'blue', 1, 0, hp: 2);
      startTurnBasedGame(w, ['red', 'blue']);
      final defeated = <UnitDefeatedEvent>[];
      final won = <VictoryEvent>[];
      w.events.on<UnitDefeatedEvent>(defeated.add);
      w.events.on<VictoryEvent>(won.add);
      w.step(0.1);
      submitOrder(w, a, AttackOrder(b));
      w.step(0.1);
      w.step(0.1);
      expect(w.entities.isAlive(b), isFalse);
      expect(defeated.single.team, 'blue');
      expect(turnStateOf(w)!.eliminated, ['blue']);
      expect(turnStateOf(w)!.winner, 'red');
      expect(won.single.team, 'red');
    },
  );

  test('after victory turns stop and orders are refused', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0);
    final b = _unit(w, 'blue', 1, 0, hp: 1);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    submitOrder(w, a, AttackOrder(b));
    w.step(0.1);
    w.step(0.1);
    expect(endTurn(w), isFalse);
    expect(submitOrder(w, a, const MoveOrder(2, 2)), isFalse);
    expect(trySpendActionPoints(w, a, 1), isFalse);
  });

  test('endTurn skips eliminated teams', () {
    final w = _world();
    _unit(w, 'red', 0, 0);
    _unit(w, 'blue', 3, 3);
    _unit(w, 'green', 5, 5);
    startTurnBasedGame(w, ['red', 'blue', 'green']);
    w.step(0.1);
    turnStateOf(w)!.eliminated.add('blue');
    endTurn(w);
    expect(turnStateOf(w)!.activeTeam, 'green');
    endTurn(w);
    expect(turnStateOf(w)!.activeTeam, 'red');
    expect(turnStateOf(w)!.round, 2);
  });

  test('a team that never had units does not trigger instant victory', () {
    final w = _world();
    _unit(w, 'red', 0, 0);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    expect(turnStateOf(w)!.winner, isNull);
    expect(turnStateOf(w)!.eliminated, isEmpty);
  });

  test('turn state with winner/eliminated round trips', () {
    final s = TurnState(['a', 'b'], eliminated: ['b'], winner: 'a');
    final back = TurnState.fromJson(s.toJson());
    expect(back.winner, 'a');
    expect(back.eliminated, ['b']);
  });
}
