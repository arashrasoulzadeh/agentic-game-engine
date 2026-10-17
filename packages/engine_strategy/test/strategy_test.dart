import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_strategy/engine_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  return w;
}

GridNavigator _nav() => GridNavigator(cols: 8, rows: 8, terrainCost: (_, _) => 1);

void main() {
  test('spawnStrategyUnit attaches the expected components', () {
    final w = _world();
    final u = spawnStrategyUnit(w,
        team: 'red', col: 2, row: 3, cellSize: 32, visionRange: 4, atlasId: 'a', spriteRegion: 'r');
    expect(w.storeOf<Team>().get(u)!.id, 'red');
    expect(w.storeOf<ActionPoints>().get(u)!.current, 0);
    expect(w.storeOf<Vision>().get(u)!.range, 4);
    expect(w.storeOf<Sprite>().has(u), isTrue);
    final p = w.storeOf<Position>().get(u)!;
    expect((p.x, p.y), (80.0, 112.0));
  });

  test('sprite and vision are optional', () {
    final w = _world();
    final u = spawnStrategyUnit(w, team: 'red', col: 0, row: 0, cellSize: 32);
    expect(w.storeOf<Vision>().has(u), isFalse);
    expect(w.storeOf<Sprite>().has(u), isFalse);
  });

  test('installStrategySystems registers systems in the documented order', () {
    final w = _world();
    final fog = installStrategySystems(w, navigator: _nav(), cellSize: 32, fog: true);
    expect(w.systemOrder,
        ['vision', 'orders', 'turn', 'winCondition', 'gridToWorld', 'selectionMarkers']);
    expect(w.storeOf<FogOfWar>().has(fog!), isTrue);
  });

  test('no fog and no markers omits those systems', () {
    final w = _world();
    final fog = installStrategySystems(w,
        navigator: _nav(), cellSize: 32, selectionMarkers: false);
    expect(fog, isNull);
    expect(w.systemOrder, ['orders', 'turn', 'winCondition', 'gridToWorld']);
  });

  test('aiTeams adds AITurnSystem after orders; a human-vs-AI round plays out', () {
    final w = _world();
    installStrategySystems(w,
        navigator: _nav(), cellSize: 32, aiTeams: {'blue': AggressiveAI()});
    expect(w.systemOrder, containsAllInOrder(['orders', 'aiTurn', 'turn']));
    final red = spawnStrategyUnit(w, team: 'red', col: 0, row: 0, cellSize: 32, maxHp: 20);
    spawnStrategyUnit(w, team: 'blue', col: 3, row: 0, cellSize: 32, attack: 4);
    startTurnBasedGame(w, ['red', 'blue']);
    endTurn(w);
    for (var i = 0; i < 4; i++) {
      w.step(0.1);
    }
    expect(turnStateOf(w)!.activeTeam, 'red');
    expect(w.storeOf<UnitStats>().get(red)!.hp, 16);
  });

  test('a full game: select, move, attack, win, through the installed systems', () {
    final w = _world();
    installStrategySystems(w, navigator: _nav(), cellSize: 32);
    final red = spawnStrategyUnit(w, team: 'red', col: 0, row: 0, cellSize: 32, attack: 5);
    final blue = spawnStrategyUnit(w, team: 'blue', col: 3, row: 0, cellSize: 32, maxHp: 4);
    startTurnBasedGame(w, ['red', 'blue']);

    final tap = GridTapController(32);
    expect(tap.handleTap(w, const Offset(16, 16)), GridTapResult.selected);
    expect(tap.handleTap(w, const Offset(3.5 * 32, 16)), GridTapResult.commanded);
    w.step(0.1);
    w.step(0.1);

    expect(w.entities.isAlive(blue), isFalse);
    expect(turnStateOf(w)!.winner, 'red');
    final g = w.storeOf<GridPosition>().get(red)!;
    expect(g.col, 2);
    expect(w.storeOf<Position>().get(red)!.x, 2.5 * 32);
    expect(w.storeOf<SelectionMarker>().length, 1);
  });
}
