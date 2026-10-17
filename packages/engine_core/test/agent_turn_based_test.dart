// The code in docs/tutorials/03-agent-driven-game.md, executed: an
// "agent" that only ever sees World.toJson() and only ever acts by
// submitting JSON orders plays a full game against the built-in AI.
import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World buildGame() {
  final world = World(width: 8, height: 8);
  registerCoreComponents(world);
  final nav = GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1);
  world.addSystem(OrderSystem.withNavigator(nav));
  world.addSystem(AITurnSystem({'blue': AggressiveAI()}));
  world.addSystem(WinConditionSystem());
  installCombat(world);

  EntityId unit(String team, int col, int row, {int hp = 10, int attack = 4}) {
    final id = world.spawn();
    world.storeOf<Team>().set(id, Team(team));
    world.storeOf<GridPosition>().set(id, GridPosition(col, row));
    world.storeOf<ActionPoints>().set(id, ActionPoints(4, current: 0));
    world.storeOf<UnitStats>().set(id, UnitStats(maxHp: hp, attack: attack));
    return id;
  }

  unit('red', 0, 0, hp: 14, attack: 5);
  unit('red', 0, 1);
  unit('blue', 6, 6, hp: 8);
  unit('blue', 7, 6, hp: 8);
  startTurnBasedGame(world, ['red', 'blue']);
  return world;
}

/// What the agent sees: plain JSON, no engine types.
Map<String, dynamic> observe(World world, String me) {
  final snapshot = world.toJson();
  final units = <Map<String, dynamic>>[];
  for (final e in snapshot['entities'] as List) {
    final c = (e['components'] as Map).cast<String, dynamic>();
    if (!c.containsKey('unitStats')) continue;
    units.add({
      'id': e['id'],
      'team': c['team']['id'],
      'col': c['gridPosition']['col'],
      'row': c['gridPosition']['row'],
      'hp': c['unitStats']['hp'],
      'ap': c['actionPoints']['current'],
    });
  }
  final turn = (snapshot['entities'] as List)
      .map((e) => (e['components'] as Map)['turnState'])
      .firstWhere((t) => t != null) as Map;
  return {'active': turn['order'][turn['activeIndex']], 'winner': turn['winner'], 'units': units};
}

/// The agent's policy: every idle unit attacks the weakest enemy. Returns
/// orders as JSON, exactly what could cross a process or network boundary.
List<Map<String, dynamic>> decide(Map<String, dynamic> view, String me) {
  final units = (view['units'] as List).cast<Map<String, dynamic>>();
  final enemies = units.where((u) => u['team'] != me).toList()
    ..sort((a, b) => (a['hp'] as int).compareTo(b['hp'] as int));
  if (enemies.isEmpty) return [];
  return [
    for (final u in units.where((u) => u['team'] == me && (u['ap'] as int) > 0))
      {'unit': u['id'], 'order': {'type': 'attack', 'target': enemies.first['id']}},
  ];
}

void main() {
  test('observe returns plain JSON that survives encode/decode', () {
    final view = observe(buildGame(), 'red');
    expect(jsonDecode(jsonEncode(view)), view);
    expect(view['active'], 'red');
    expect((view['units'] as List), hasLength(4));
  });

  test('a JSON-only agent beats the built-in AI', () {
    final world = buildGame();
    for (var round = 0; round < 12; round++) {
      final view = observe(world, 'red');
      if (view['winner'] != null) break;
      for (final move in decide(view, 'red')) {
        final accepted = submitOrder(
          world,
          move['unit'] as int,
          Order.fromJson((move['order'] as Map).cast<String, dynamic>()),
        );
        expect(accepted, isTrue);
      }
      world.step(1 / 60);
      endTurn(world);
      for (var i = 0; i < 4; i++) {
        world.step(1 / 60);
      }
    }
    expect(observe(world, 'red')['winner'], 'red');
  });

  test('the agent cannot act out of turn: the engine refuses', () {
    final world = buildGame();
    final blueUnit = (observe(world, 'red')['units'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((u) => u['team'] == 'blue')['id'] as int;
    expect(submitOrder(world, blueUnit, const MoveOrder(5, 5)), isFalse);
  });

  test('a bad order is a FormatException, not corrupted state', () {
    expect(() => Order.fromJson({'type': 'teleport'}), throwsFormatException);
  });
}
