import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// [corridor] makes column 5 the only walkable column, so a runner's path is
/// forced (A* otherwise wanders between equal-cost routes) and the cell where it
/// first comes into range is exactly predictable.
World _world({bool fog = false, bool corridor = false}) {
  final w = World(width: 20, height: 20);
  registerCoreComponents(w);
  if (fog) {
    w.storeOf<FogOfWar>().set(w.spawn(), FogOfWar(20, 20));
    w.addSystem(VisionSystem());
  }
  w.addSystem(OrderSystem.withNavigator(GridNavigator(cols: 20, rows: 20, terrainCost: (c, r) => !corridor || c == 5 ? 1 : null)));
  installCombat(w);
  return w;
}

EntityId _unit(World w, String team, int c, int r,
    {int ap = 4, int hp = 20, int atk = 5, int def = 0, int? vision}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(ap, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: hp, attack: atk, defense: def));
  if (vision != null) w.storeOf<Vision>().set(e, Vision(vision));
  return e;
}

void main() {
  test('OverwatchOrder spends all points, sets the stance, and round-trips JSON', () {
    final w = _world();
    final guard = _unit(w, 'red', 0, 0, ap: 3);
    _unit(w, 'blue', 9, 9);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, guard, const OverwatchOrder());
    w.step(0.1);
    expect(w.storeOf<ActionPoints>().get(guard)!.current, 0);
    expect(w.storeOf<StatusEffects>().get(guard)!.has(overwatchStatus), isTrue);
    expect(Order.fromJson(const OverwatchOrder().toJson()), isA<OverwatchOrder>());
  });

  /// Number of steps the unit took, counted from `MovedEvent`s.
  int stepsOf(World w, EntityId e, void Function() act) {
    var n = 0;
    w.events.on<MovedEvent>((m) {
      if (m.entity == e) n++;
    });
    act();
    w.events.flush();
    return n;
  }

  test('the first enemy to step into range is shot and stopped mid-path', () {
    final w = _world(corridor: true);
    final guard = _unit(w, 'red', 6, 5, ap: 2, atk: 20);
    final runner = _unit(w, 'blue', 5, 0, hp: 15, ap: 9);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, guard, const OverwatchOrder());
    w.step(0.1);

    final triggered = <OverwatchTriggeredEvent>[];
    w.events.on<OverwatchTriggeredEvent>(triggered.add);
    endTurn(w);
    submitOrder(w, runner, const MoveOrder(5, 9));
    final steps = stepsOf(w, runner, () => w.step(0.1));

    expect(w.entities.isAlive(runner), isFalse, reason: '20 damage kills a 15 hp runner');
    expect(steps, 4, reason: 'row 4 is the first cell within 1 of (6,5); it never took step 5');
    expect(triggered.single.watcher, guard);
    expect(triggered.single.target, runner);
    expect(w.storeOf<StatusEffects>().get(guard)!.has(overwatchStatus), isFalse,
        reason: 'the stance ends on firing');
  });

  test('a survivor is hit exactly once and carries on with its next order', () {
    final w = _world(corridor: true);
    final guard = _unit(w, 'red', 6, 5, ap: 2, atk: 4);
    final runner = _unit(w, 'blue', 5, 0, hp: 30, ap: 12);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, guard, const OverwatchOrder());
    w.step(0.1);
    endTurn(w);
    submitOrder(w, runner, const MoveOrder(5, 4));
    submitOrder(w, runner, const MoveOrder(5, 9));
    w.step(0.1);
    expect(w.storeOf<UnitStats>().get(runner)!.hp, 26, reason: 'one shot of 4, then the stance is spent');
    expect(w.storeOf<GridPosition>().get(runner)!.row, 9);
  });

  test('a longer-ranged watcher (AttackProfile) fires earlier', () {
    final w = _world(corridor: true);
    final archer = _unit(w, 'red', 6, 5, ap: 2, atk: 99);
    w.storeOf<AttackProfile>().set(archer, AttackProfile(range: 3));
    final runner = _unit(w, 'blue', 5, 0, hp: 50, ap: 9);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, archer, const OverwatchOrder());
    w.step(0.1);
    endTurn(w);
    submitOrder(w, runner, const MoveOrder(5, 9));
    final steps = stepsOf(w, runner, () => w.step(0.1));
    expect(w.entities.isAlive(runner), isFalse);
    expect(steps, 2, reason: 'row 2 is first within range 3 of (6,5)');
  });

  test('enemies out of range, friends, and the unwatched are ignored', () {
    final w = _world();
    final guard = _unit(w, 'red', 0, 0, ap: 2);
    final friend = _unit(w, 'red', 0, 3, ap: 4);
    _unit(w, 'blue', 15, 15);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, guard, const OverwatchOrder());
    w.step(0.1);
    submitOrder(w, friend, const MoveOrder(0, 1));
    w.step(0.1);
    expect(w.storeOf<UnitStats>().get(friend)!.hp, 20, reason: 'friendly movement never triggers it');
    expect(w.storeOf<StatusEffects>().get(guard)!.has(overwatchStatus), isTrue);
  });

  test('the stance lapses at the owner\'s next turn start if nothing came', () {
    final w = _world();
    final guard = _unit(w, 'red', 0, 0, ap: 2);
    _unit(w, 'blue', 15, 15);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, guard, const OverwatchOrder());
    w.step(0.1);
    endTurn(w);
    endTurn(w);
    expect(w.storeOf<StatusEffects>().get(guard)!.has(overwatchStatus), isFalse);
  });

  test('fog: a watcher only shoots what its team can see', () {
    int runnerHp(int watcherVision) {
      final w = _world(fog: true, corridor: true);
      final guard = _unit(w, 'red', 6, 5, ap: 2, vision: watcherVision);
      final runner = _unit(w, 'blue', 5, 0, hp: 30, ap: 9);
      startTurnBasedGame(w, ['red', 'blue']);
      w.step(0.1);
      submitOrder(w, guard, const OverwatchOrder());
      w.step(0.1);
      endTurn(w);
      submitOrder(w, runner, const MoveOrder(5, 9));
      w.step(0.1);
      return w.storeOf<UnitStats>().get(runner)!.hp;
    }

    expect(runnerHp(0), 30, reason: 'vision 0 sees only its own cell');
    expect(runnerHp(2), lessThan(30), reason: 'vision 2 reaches the corridor cell (5,4)');
  });

  test('approaching an attack target also triggers overwatch', () {
    final w = _world(corridor: true);
    final guard = _unit(w, 'red', 6, 5, ap: 2, atk: 4);
    final other = _unit(w, 'red', 5, 9, ap: 2);
    final runner = _unit(w, 'blue', 5, 0, hp: 30, ap: 12, atk: 1);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, guard, const OverwatchOrder());
    w.step(0.1);
    endTurn(w);
    submitOrder(w, runner, AttackOrder(other));
    w.step(0.1);
    expect(w.storeOf<UnitStats>().get(runner)!.hp, 26);
  });

  test('with no points left it waits for next turn, like defend', () {
    final w = _world();
    final guard = _unit(w, 'red', 0, 0, ap: 2);
    _unit(w, 'blue', 15, 15);
    startTurnBasedGame(w, ['red', 'blue']);
    trySpendActionPoints(w, guard, 2);
    submitOrder(w, guard, const OverwatchOrder());
    w.step(0.1);
    expect(w.storeOf<OrderQueue>().get(guard)!.orders, hasLength(1));
    endTurn(w);
    endTurn(w);
    w.step(0.1);
    expect(w.storeOf<StatusEffects>().get(guard)!.has(overwatchStatus), isTrue);
  });

  test('a unit without ActionPoints cannot take the stance', () {
    final w = _world();
    final e = _unit(w, 'red', 0, 0);
    w.storeOf<ActionPoints>().remove(e);
    _unit(w, 'blue', 9, 9);
    startTurnBasedGame(w, ['red', 'blue']);
    final failed = <OrderFailedEvent>[];
    w.events.on<OrderFailedEvent>(failed.add);
    w.storeOf<OrderQueue>().set(e, OrderQueue([const OverwatchOrder()]));
    w.step(0.1);
    expect(failed.single.reason, OrderFailure.invalidTarget);
  });

  test('resolveAttack applies damage immediately and defeats at zero', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0, atk: 30);
    final b = _unit(w, 'blue', 1, 0, hp: 10);
    final defeated = <UnitDefeatedEvent>[];
    w.events.on<UnitDefeatedEvent>(defeated.add);
    resolveAttack(w, a, b);
    expect(w.entities.isAlive(b), isFalse);
    w.events.flush();
    expect(defeated.single.unit, b);
  });
}
