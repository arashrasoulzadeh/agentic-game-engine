import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world({bool Function(int, int)? walls}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  w.addSystem(VisionSystem(blocksSight: walls ?? (_, __) => false));
  w.addSystem(OrderSystem());
  final fog = w.spawn();
  w.storeOf<FogOfWar>().set(fog, FogOfWar(10, 10));
  return w;
}

EntityId _unit(World w, String team, int c, int r, {int? vision}) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(5, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  if (vision != null) w.storeOf<Vision>().set(e, Vision(vision));
  return e;
}

void main() {
  test('line of sight: endpoints never block, interior walls do', () {
    bool wall(int c, int r) => c == 2 && r == 0;
    expect(hasGridLineOfSight(0, 0, 4, 0, wall), isFalse);
    expect(hasGridLineOfSight(0, 0, 2, 0, wall), isTrue);
    expect(hasGridLineOfSight(0, 0, 4, 2, wall), isTrue);
    expect(hasGridLineOfSight(3, 3, 3, 3, wall), isTrue);
  });

  test('vision reveals a circle and ignores out-of-range/other teams', () {
    final w = _world();
    _unit(w, 'red', 5, 5, vision: 2);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    final fog = fogOf(w)!;
    expect(fog.isVisible('red', 5, 5), isTrue);
    expect(fog.isVisible('red', 7, 5), isTrue);
    expect(fog.isVisible('red', 7, 7), isFalse);
    expect(fog.isVisible('red', 8, 5), isFalse);
    expect(fog.isVisible('blue', 5, 5), isFalse);
  });

  test('walls block sight; visible is recomputed but explored persists', () {
    final w = _world(walls: (c, r) => c == 6 && r == 5);
    final a = _unit(w, 'red', 5, 5, vision: 3);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    final fog = fogOf(w)!;
    expect(fog.isVisible('red', 6, 5), isTrue);
    expect(fog.isVisible('red', 8, 5), isFalse);
    w.storeOf<GridPosition>().get(a)!
      ..col = 0
      ..row = 0;
    w.step(0.1);
    expect(fog.isVisible('red', 5, 5), isFalse);
    expect(fog.isExplored('red', 5, 5), isTrue);
  });

  test('canSee: own units and visible enemies yes, hidden enemies no, no fog = yes', () {
    final w = _world();
    _unit(w, 'red', 0, 0, vision: 2);
    final mine = _unit(w, 'red', 9, 9);
    final near = _unit(w, 'blue', 1, 1);
    final far = _unit(w, 'blue', 8, 8);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    expect(canSee(w, 'red', mine), isTrue);
    expect(canSee(w, 'red', near), isTrue);
    expect(canSee(w, 'red', far), isFalse);

    final noFog = World(width: 5, height: 5);
    registerCoreComponents(noFog);
    expect(canSee(noFog, 'red', far), isTrue);
  });

  test('attacking an unseen enemy fails', () {
    final w = _world();
    final a = _unit(w, 'red', 0, 0, vision: 1);
    final hidden = _unit(w, 'blue', 2, 0);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    final failed = <OrderFailedEvent>[];
    w.events.on<OrderFailedEvent>(failed.add);
    submitOrder(w, a, AttackOrder(hidden));
    w.step(0.1);
    expect(failed.single.reason, OrderFailure.invalidTarget);
  });

  test('FogOfWar round trips', () {
    final f = FogOfWar(4, 4, visible: {'a': {1, 2}}, explored: {'a': {1, 2, 3}});
    final back = FogOfWar.fromJson(f.toJson());
    expect(back.isVisible('a', 2, 0), isTrue);
    expect(back.isExplored('a', 3, 0), isTrue);
    expect(back.isVisible('a', 3, 0), isFalse);
  });
}
