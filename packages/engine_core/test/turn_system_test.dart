import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  return w;
}

EntityId _unit(World w, String team, int ap) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  return e;
}

void main() {
  test('starting refills only the first team and emits TurnStartedEvent', () {
    final w = _world();
    final a = _unit(w, 'red', 3);
    final b = _unit(w, 'blue', 3);
    final started = <TurnStartedEvent>[];
    w.events.on<TurnStartedEvent>(started.add);
    startTurnBasedGame(w, ['red', 'blue']);
    w.events.flush();
    expect(w.storeOf<ActionPoints>().get(a)!.current, 3);
    expect(w.storeOf<ActionPoints>().get(b)!.current, 0);
    expect(started.single.team, 'red');
  });

  test('endTurn advances, refills, and increments round on wrap', () {
    final w = _world();
    final a = _unit(w, 'red', 2);
    final b = _unit(w, 'blue', 2);
    startTurnBasedGame(w, ['red', 'blue']);
    final ended = <TurnEndedEvent>[];
    w.events.on<TurnEndedEvent>(ended.add);
    endTurn(w);
    expect(turnStateOf(w)!.activeTeam, 'blue');
    expect(w.storeOf<ActionPoints>().get(b)!.current, 2);
    endTurn(w);
    w.events.flush();
    expect(turnStateOf(w)!.activeTeam, 'red');
    expect(turnStateOf(w)!.round, 2);
    expect(w.storeOf<ActionPoints>().get(a)!.current, 2);
    expect(ended.map((e) => e.team), ['red', 'blue']);
  });

  test('spending is rejected out of turn and when over budget', () {
    final w = _world();
    final a = _unit(w, 'red', 2);
    final b = _unit(w, 'blue', 2);
    startTurnBasedGame(w, ['red', 'blue']);
    expect(trySpendActionPoints(w, b, 1), isFalse);
    expect(trySpendActionPoints(w, a, 3), isFalse);
    expect(w.storeOf<ActionPoints>().get(a)!.current, 2);
    expect(trySpendActionPoints(w, a, 2), isTrue);
    expect(trySpendActionPoints(w, a, 1), isFalse);
  });

  test('TurnSystem auto-ends only listed teams once all are spent', () {
    final w = _world();
    final a1 = _unit(w, 'red', 1);
    final a2 = _unit(w, 'red', 1);
    _unit(w, 'blue', 1);
    w.addSystem(TurnSystem(autoEndTeams: {'red'}));
    startTurnBasedGame(w, ['red', 'blue']);
    trySpendActionPoints(w, a1, 1);
    w.step(0.1);
    expect(turnStateOf(w)!.activeTeam, 'red');
    trySpendActionPoints(w, a2, 1);
    w.step(0.1);
    expect(turnStateOf(w)!.activeTeam, 'blue');
    w.step(0.1);
    expect(turnStateOf(w)!.activeTeam, 'blue');
  });

  test('turn state survives a JSON round trip', () {
    final w = _world();
    _unit(w, 'red', 2);
    startTurnBasedGame(w, ['red', 'blue']);
    endTurn(w);
    final w2 = _world();
    for (final _ in w.entities.all) {
      w2.spawn();
    }
    w2.applyPatch(w.toJson());
    expect(turnStateOf(w2)!.activeTeam, 'blue');
  });

  test('empty team order is rejected', () {
    expect(() => startTurnBasedGame(_world(), []), throwsArgumentError);
  });
}
