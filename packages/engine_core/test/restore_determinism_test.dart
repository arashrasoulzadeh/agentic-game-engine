// A world rebuilt from a snapshot has the same data but a different store
// iteration order (ComponentStore order depends on add/remove history). Systems
// that decide anything by "who goes first" must not depend on it, or rollback,
// replay and lockstep silently diverge. These tests pin that for the turn-based
// order system and the AIs.
import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GridNavigator _nav() => GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1);

World _skirmish() {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  w.addSystem(OrderSystem.withNavigator(_nav()));
  w.addSystem(AITurnSystem({
    'red': TacticalAI(navigator: _nav()),
    'blue': AggressiveAI(),
  }));
  w.addSystem(WinConditionSystem());
  installCombat(w);
  for (var i = 0; i < 6; i++) {
    for (final (team, col) in [('red', 1), ('blue', 10)]) {
      final e = w.spawn();
      w.storeOf<Team>().set(e, Team(team));
      w.storeOf<ActionPoints>().set(e, ActionPoints(4, current: 0));
      w.storeOf<GridPosition>().set(e, GridPosition(col, 3 + i));
      w.storeOf<UnitStats>().set(e, UnitStats(maxHp: 12, attack: 3));
    }
  }
  startTurnBasedGame(w, ['red', 'blue']);
  return w;
}

String _fingerprint(World w) => jsonEncode(WorldSnapshot.capture(w).toJson());

void _play(World w, int steps) {
  for (var i = 0; i < steps; i++) {
    w.step(0.1);
  }
}

void main() {
  test('a snapshot restored into a fresh world replays an AI-vs-AI game identically', () {
    final original = _skirmish();
    _play(original, 40);
    final midpoint = WorldSnapshot.capture(original);
    _play(original, 120);

    final rebuilt = _skirmish();
    midpoint.restoreInto(rebuilt);
    _play(rebuilt, 120);

    expect(_fingerprint(rebuilt), _fingerprint(original));
  });

  test('churning the stores before a restore does not change the outcome', () {
    final a = _skirmish();
    _play(a, 30);
    final snap = WorldSnapshot.capture(a);

    // Churn b's stores so its dense order differs wildly from a's.
    final b = _skirmish();
    for (var i = 0; i < 20; i++) {
      final junk = b.spawn();
      b.storeOf<Team>().set(junk, Team('red'));
      b.storeOf<GridPosition>().set(junk, GridPosition(0, 0));
    }
    snap.restoreInto(b);
    _play(a, 100);
    _play(b, 100);
    expect(_fingerprint(b), _fingerprint(a));
  });
}
