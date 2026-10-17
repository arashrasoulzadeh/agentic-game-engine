import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() => GridNavigator(cols: 20, rows: 20, terrainCost: (c, r) => 1);

World _battle({Map<String, TurnAI>? ai, double interval = 1.0, int perSide = 5}) {
  final w = World(width: 20, height: 20);
  registerCoreComponents(w);
  w.addSystem(RealtimeAISystem(ai ?? {'blue': AggressiveAI(), 'red': AggressiveAI()}, interval: interval));
  w.addSystem(RealtimeOrderSystem(fields: FlowFieldCache(_nav())));
  w.addSystem(LastTeamStandingSystem());
  for (var i = 0; i < perSide; i++) {
    spawnRealtimeUnit(w, team: 'red', col: 1, row: 2 + i, speed: 3, attack: 3, maxHp: 12);
    spawnRealtimeUnit(w, team: 'blue', col: 18, row: 2 + i, speed: 3, attack: 3, maxHp: 12);
  }
  return w;
}

String _fingerprint(World w) => jsonEncode(WorldSnapshot.capture(w).toJson());

void main() {
  group('RealtimeAISystem', () {
    test('acts once per interval, not every tick', () {
      var calls = 0;
      final counter = _CountingAI(() => calls++);
      final w = World(width: 5, height: 5);
      registerCoreComponents(w);
      w.addSystem(RealtimeAISystem({'blue': counter}, interval: 1.0));
      for (var i = 0; i < 10; i++) {
        w.step(0.1);
      }
      expect(calls, 1, reason: 'ten 0.1 s steps reach exactly one second despite float rounding');
      for (var i = 0; i < 20; i++) {
        w.step(0.1);
      }
      expect(calls, 3);
    });

    test('teams are visited in name order, so decisions do not depend on map insertion order', () {
      final order = <String>[];
      final w = World(width: 5, height: 5);
      registerCoreComponents(w);
      w.addSystem(RealtimeAISystem({
        'zeta': _CountingAI(() => order.add('zeta')),
        'alpha': _CountingAI(() => order.add('alpha')),
      }, interval: 0.5));
      w.step(0.5);
      expect(order, ['alpha', 'zeta']);
    });

    test('an AI-vs-AI real-time battle ends with a winner', () {
      final w = _battle();
      final victories = <VictoryEvent>[];
      w.events.on<VictoryEvent>(victories.add);
      for (var i = 0; i < 1200 && victories.isEmpty; i++) {
        w.step(0.05);
      }
      expect(victories, hasLength(1));
      expect(w.storeOf<UnitStats>().length, lessThan(10));
    });

    test('units without action points are treated as always able to act', () {
      final w = _battle(ai: {'blue': AggressiveAI()}, perSide: 1);
      w.step(1.0);
      final blue = [
        for (var i = 0; i < w.storeOf<Team>().length; i++)
          if (w.storeOf<Team>().denseAt(i).id == 'blue') w.storeOf<Team>().entityAt(i),
      ].single;
      expect(w.storeOf<ActionPoints>().has(blue), isFalse);
      expect(w.storeOf<OrderQueue>().get(blue)!.orders.single, isA<AttackOrder>());
    });

    test('the same game twice is identical (the AI is deterministic in real time)', () {
      final a = _battle(), b = _battle();
      for (var i = 0; i < 400; i++) {
        a.step(0.05);
        b.step(0.05);
      }
      expect(_fingerprint(a), _fingerprint(b));
    });

    test('TacticalAI retreats and ObjectiveAI marches in real time too', () {
      final w = World(width: 20, height: 20);
      registerCoreComponents(w);
      final weak = spawnRealtimeUnit(w, team: 'blue', col: 10, row: 10, maxHp: 10);
      w.storeOf<UnitStats>().get(weak)!.hp = 1;
      final foe = spawnRealtimeUnit(w, team: 'red', col: 12, row: 10);
      TacticalAI(navigator: _nav()).playTurn(w, 'blue');
      final move = w.storeOf<OrderQueue>().get(weak)!.orders.single as MoveOrder;
      expect(GridPosition(move.col, move.row).chebyshev(w.storeOf<GridPosition>().get(foe)!),
          greaterThan(2), reason: 'ran away');
      expect(GridPosition(move.col, move.row).chebyshev(GridPosition(10, 10)), lessThanOrEqualTo(4),
          reason: 'within the real-time retreat budget');

      final w2 = World(width: 20, height: 20);
      registerCoreComponents(w2);
      w2.storeOf<Objective>().set(w2.spawn(), Objective('hill', 15, 15));
      final marcher = spawnRealtimeUnit(w2, team: 'blue', col: 2, row: 2);
      spawnRealtimeUnit(w2, team: 'red', col: 19, row: 0);
      ObjectiveAI(navigator: _nav()).playTurn(w2, 'blue');
      final goal = w2.storeOf<OrderQueue>().get(marcher)!.orders.first as MoveOrder;
      expect((goal.col, goal.row), (15, 15));
    });
  });
}

class _CountingAI implements TurnAI {
  _CountingAI(this.onPlay);
  final void Function() onPlay;
  @override
  void playTurn(World world, String team) => onPlay();
}
