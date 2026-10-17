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
  moveRangeTests();
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

  test('attackRange / attackCost attach an AttackProfile; omitted they do not', () {
    final w = _world();
    final archer = spawnStrategyUnit(w, team: 'red', col: 0, row: 0, cellSize: 32, attackRange: 3);
    final mage = spawnStrategyUnit(w, team: 'red', col: 1, row: 0, cellSize: 32, attackCost: 2);
    final knight = spawnStrategyUnit(w, team: 'red', col: 2, row: 0, cellSize: 32);
    expect(w.storeOf<AttackProfile>().get(archer)!.range, 3);
    expect(w.storeOf<AttackProfile>().get(archer)!.cost, 1);
    expect(w.storeOf<AttackProfile>().get(mage)!.cost, 2);
    expect(w.storeOf<AttackProfile>().get(mage)!.range, 1);
    expect(w.storeOf<AttackProfile>().has(knight), isFalse);
  });

  test('an archer shoots over a gap a knight cannot, through the installed systems', () {
    final w = _world();
    installStrategySystems(w, navigator: _nav(), cellSize: 32);
    final archer = spawnStrategyUnit(w, team: 'red', col: 0, row: 0, cellSize: 32, attackRange: 4);
    final foe = spawnStrategyUnit(w, team: 'blue', col: 4, row: 0, cellSize: 32, maxHp: 10);
    startTurnBasedGame(w, ['red', 'blue']);
    submitOrder(w, archer, AttackOrder(foe));
    w.step(0.1);
    expect(w.storeOf<UnitStats>().get(foe)!.hp, 7);
    expect(w.storeOf<GridPosition>().get(archer)!.col, 0);
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

void moveRangeTests() {
  Set<(int, int)> lit(World w) {
    final markers = w.storeOf<MoveRangeMarker>();
    return {
      for (var i = 0; i < markers.length; i++)
        (
          (w.storeOf<Position>().get(markers.entityAt(i))!.x / 32 - 0.5).round(),
          (w.storeOf<Position>().get(markers.entityAt(i))!.y / 32 - 0.5).round(),
        ),
    };
  }

  World setup(void Function(World w) extra) {
    final w = _world();
    installStrategySystems(
      w,
      navigator: _nav(),
      cellSize: 32,
      moveHighlight: (atlasId: 'terrain', region: 'highlight'),
    );
    extra(w);
    return w;
  }

  test('selecting a unit lights up exactly the cells it can reach; deselecting clears them', () {
    final w = setup((_) {});
    final u = spawnStrategyUnit(w, team: 'red', col: 3, row: 3, cellSize: 32, actionPoints: 1);
    spawnStrategyUnit(w, team: 'blue', col: 7, row: 7, cellSize: 32);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    expect(lit(w), isEmpty);

    selectAtCell(w, 3, 3);
    w.step(0.1);
    final expected = _nav().reachable(GridPosition(3, 3), 1).keys.toSet();
    expect(lit(w), expected);
    expect(lit(w).length, 8);
    expect(w.storeOf<Sprite>().get(w.storeOf<MoveRangeMarker>().entityAt(0))!.region, 'highlight');

    clearSelection(w);
    w.step(0.1);
    expect(lit(w), isEmpty);
    expect(w.storeOf<Team>().has(u), isTrue);
  });

  test('occupied cells are not lit, and the highlight shrinks as points are spent', () {
    final w = setup((_) {});
    final u = spawnStrategyUnit(w, team: 'red', col: 3, row: 3, cellSize: 32, actionPoints: 2);
    spawnStrategyUnit(w, team: 'red', col: 4, row: 3, cellSize: 32);
    spawnStrategyUnit(w, team: 'blue', col: 7, row: 7, cellSize: 32);
    startTurnBasedGame(w, ['red', 'blue']);
    selectAtCell(w, 3, 3);
    w.step(0.1);
    final full = lit(w);
    expect(full.contains((4, 3)), isFalse);

    trySpendActionPoints(w, u, 1);
    w.step(0.1);
    expect(lit(w).length, lessThan(full.length));
  });

  test('a multi-selection or a unit with no points shows nothing', () {
    final w = setup((_) {});
    spawnStrategyUnit(w, team: 'red', col: 0, row: 0, cellSize: 32);
    spawnStrategyUnit(w, team: 'red', col: 1, row: 0, cellSize: 32);
    spawnStrategyUnit(w, team: 'blue', col: 7, row: 7, cellSize: 32);
    startTurnBasedGame(w, ['red', 'blue']);
    selectInBox(w, 0, 0, 1, 0);
    w.step(0.1);
    expect(lit(w), isEmpty);
    selectAtCell(w, 0, 0);
    trySpendActionPoints(w, selectedEntities(w).single, 3);
    w.step(0.1);
    expect(lit(w), isEmpty);
  });

  test('without moveHighlight the system and component are absent', () {
    final w = _world();
    installStrategySystems(w, navigator: _nav(), cellSize: 32);
    expect(w.systemOrder.contains('moveRangeHighlight'), isFalse);
  });

  test('installing twice does not double-register the marker component', () {
    final w = _world();
    installStrategySystems(w, navigator: _nav(), cellSize: 32, moveHighlight: (atlasId: 'a', region: 'b'));
    installStrategySystems(w, navigator: _nav(), cellSize: 32, moveHighlight: (atlasId: 'a', region: 'b'));
    expect(w.components.all.where((r) => r.name == 'moveRangeMarker'), hasLength(1));
  });
}
