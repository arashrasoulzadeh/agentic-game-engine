import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_strategy/engine_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

const _shade = (
  team: 'red',
  atlasId: 'terrain',
  unknownRegion: 'fog_unknown',
  exploredRegion: 'fog_explored',
  clearRegion: 'fog_clear',
);

World _game({Set<(int, int)> walls = const {}}) {
  final w = World(width: 320, height: 320);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  installStrategySystems(
    w,
    navigator: GridNavigator(cols: 10, rows: 10, terrainCost: (c, r) => 1),
    cellSize: 32,
    fog: true,
    blocksSight: (c, r) => walls.contains((c, r)),
    fogShade: _shade,
  );
  return w;
}

String _regionAt(World w, int col, int row) {
  final cells = w.storeOf<FogShadeCell>();
  for (var i = 0; i < cells.length; i++) {
    if (cells.denseAt(i).col == col && cells.denseAt(i).row == row) {
      return w.storeOf<Sprite>().get(cells.entityAt(i))!.region;
    }
  }
  throw StateError('no tile at $col,$row');
}

void main() {
  test('one tile per cell, shaded by what the team has seen', () {
    final w = _game();
    spawnStrategyUnit(w, team: 'red', col: 2, row: 2, cellSize: 32, visionRange: 2);
    spawnStrategyUnit(w, team: 'blue', col: 9, row: 9, cellSize: 32);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);

    expect(w.storeOf<FogShadeCell>().length, 100);
    expect(_regionAt(w, 2, 2), 'fog_clear');
    expect(_regionAt(w, 3, 2), 'fog_clear');
    expect(_regionAt(w, 8, 8), 'fog_unknown');
  });

  test('cells the team saw and left become "explored", not unknown again', () {
    final w = _game();
    final scout = spawnStrategyUnit(w, team: 'red', col: 1, row: 1, cellSize: 32, visionRange: 1);
    spawnStrategyUnit(w, team: 'blue', col: 9, row: 9, cellSize: 32);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    expect(_regionAt(w, 1, 1), 'fog_clear');

    w.storeOf<GridPosition>().get(scout)!
      ..col = 5
      ..row = 5;
    w.step(0.1);
    expect(_regionAt(w, 1, 1), 'fog_explored');
    expect(_regionAt(w, 5, 5), 'fog_clear');
    expect(_regionAt(w, 9, 0), 'fog_unknown');
  });

  test('walls cast shadow', () {
    final w = _game(walls: {(3, 2)});
    spawnStrategyUnit(w, team: 'red', col: 1, row: 2, cellSize: 32, visionRange: 4);
    spawnStrategyUnit(w, team: 'blue', col: 9, row: 9, cellSize: 32);
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    expect(_regionAt(w, 3, 2), 'fog_clear', reason: 'the wall itself is seen');
    expect(_regionAt(w, 5, 2), 'fog_unknown', reason: 'behind the wall');
  });

  test('enemies standing in fog lose their sprite, and get it back, intact, when seen', () {
    final w = _game();
    spawnStrategyUnit(w, team: 'red', col: 0, row: 0, cellSize: 32, visionRange: 2);
    final foe = spawnStrategyUnit(w, team: 'blue', col: 6, row: 0, cellSize: 32, atlasId: 'units', spriteRegion: 'blue');
    final friend = spawnStrategyUnit(w, team: 'red', col: 8, row: 8, cellSize: 32, atlasId: 'units', spriteRegion: 'red');
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);

    expect(w.storeOf<Sprite>().has(foe), isFalse);
    expect(w.storeOf<FogHidden>().get(foe)!.sprite.region, 'blue');
    expect(w.storeOf<Sprite>().has(friend), isTrue, reason: 'your own units are never hidden');

    w.storeOf<GridPosition>().get(foe)!.col = 2;
    w.step(0.1);
    expect(w.storeOf<Sprite>().get(foe)!.region, 'blue');
    expect(w.storeOf<FogHidden>().has(foe), isFalse);
  });

  test('a hidden enemy survives a save: FogHidden serializes through World.toJson', () {
    final w = _game();
    spawnStrategyUnit(w, team: 'red', col: 0, row: 0, cellSize: 32, visionRange: 1);
    final foe = spawnStrategyUnit(w, team: 'blue', col: 9, row: 9, cellSize: 32, atlasId: 'units', spriteRegion: 'blue');
    startTurnBasedGame(w, ['red', 'blue']);
    w.step(0.1);
    final saved = w.toJson();
    final entity = (saved['entities'] as List).firstWhere((e) => e['id'] == foe);
    expect(entity['components']['fogHidden']['sprite']['region'], 'blue');
    expect(entity['components'].containsKey('sprite'), isFalse);
  });

  test('hideEnemies: false only shades', () {
    final w = World(width: 320, height: 320);
    registerCoreComponents(w);
    registerFlutterComponents(w);
    w.storeOf<FogOfWar>().set(w.spawn(), FogOfWar(4, 4));
    w.addSystem(VisionSystem());
    w.addSystem(FogShadeSystem(
      team: 'red',
      cellSize: 32,
      atlasId: 'a',
      unknownRegion: 'u',
      exploredRegion: 'e',
      clearRegion: 'c',
      hideEnemies: false,
    ));
    w.components.register<FogShadeCell>('fogShadeCell', (c) => c.toJson(), FogShadeCell.fromJson);
    final foe = w.spawn();
    w.storeOf<Team>().set(foe, Team('blue'));
    w.storeOf<Sprite>().set(foe, Sprite('x', 'y'));
    w.step(0.1);
    expect(w.storeOf<Sprite>().has(foe), isTrue);
  });

  test('without a FogOfWar entity it does nothing, and a resized fog rebuilds the tiles', () {
    final w = World(width: 320, height: 320);
    registerCoreComponents(w);
    registerFlutterComponents(w);
    w.components.register<FogShadeCell>('fogShadeCell', (c) => c.toJson(), FogShadeCell.fromJson);
    w.components.register<FogHidden>('fogHidden', (h) => h.toJson(), FogHidden.fromJson);
    w.addSystem(FogShadeSystem(
        team: 'red', cellSize: 32, atlasId: 'a', unknownRegion: 'u', exploredRegion: 'e', clearRegion: 'c'));
    w.step(0.1);
    expect(w.storeOf<FogShadeCell>().length, 0);

    final fogEntity = w.spawn();
    w.storeOf<FogOfWar>().set(fogEntity, FogOfWar(3, 3));
    w.step(0.1);
    expect(w.storeOf<FogShadeCell>().length, 9);
    w.storeOf<FogOfWar>().set(fogEntity, FogOfWar(4, 2));
    w.step(0.1);
    expect(w.storeOf<FogShadeCell>().length, 8);
  });

  test('FogShadeCell JSON round-trips; fogShade without fog is rejected; double install is safe', () {
    final back = FogShadeCell.fromJson(FogShadeCell(2, 3, FogCellState.explored).toJson());
    expect((back.col, back.row, back.state), (2, 3, FogCellState.explored));
    expect(FogShadeCell.fromJson({'col': 0, 'row': 0, 'state': 'bogus'}).state, FogCellState.unknown);

    final w = World(width: 10, height: 10);
    registerCoreComponents(w);
    registerFlutterComponents(w);
    expect(
      () => installStrategySystems(w,
          navigator: GridNavigator(cols: 2, rows: 2, terrainCost: (c, r) => 1), cellSize: 32, fogShade: _shade),
      throwsArgumentError,
    );
    final ok = _game();
    installStrategySystems(ok,
        navigator: GridNavigator(cols: 10, rows: 10, terrainCost: (c, r) => 1),
        cellSize: 32,
        fog: true,
        fogShade: _shade);
    expect(ok.components.all.where((r) => r.name == 'fogShadeCell'), hasLength(1));
  });
}
