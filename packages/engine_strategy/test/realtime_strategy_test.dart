
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_strategy/engine_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

World _world() {
  final w = World(width: 640, height: 640);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  return w;
}

GridNavigator _nav() => GridNavigator(cols: 20, rows: 20, terrainCost: (c, r) => 1);

void main() {
  test('registers the real-time systems in the documented order, with no turn systems', () {
    final w = _world();
    installRealtimeStrategySystems(w, navigator: _nav(), cellSize: 32);
    expect(w.systemOrder, ['realtimeOrders', 'lastTeamStanding', 'gridToWorld', 'selectionMarkers']);
    expect(turnStateOf(w), isNull);
  });

  test('fog adds vision first and shading last; fogShade without fog is rejected', () {
    final w = _world();
    final install = installRealtimeStrategySystems(
      w,
      navigator: _nav(),
      cellSize: 32,
      fog: true,
      selectionMarkers: false,
      fogShade: (
        team: 'red',
        atlasId: 't',
        unknownRegion: 'u',
        exploredRegion: 'e',
        clearRegion: 'c',
      ),
    );
    expect(w.systemOrder.first, 'vision');
    expect(w.systemOrder.last, 'fogShade');
    expect(w.storeOf<FogOfWar>().has(install.fog!), isTrue);

    expect(
      () => installRealtimeStrategySystems(_world(),
          navigator: _nav(),
          cellSize: 32,
          fogShade: (team: 'r', atlasId: 'a', unknownRegion: 'u', exploredRegion: 'e', clearRegion: 'c')),
      throwsArgumentError,
    );
  });

  test('spawnStrategyUnit(realtime:) gives RealtimeStats and no action points', () {
    final w = _world();
    final u = spawnStrategyUnit(w,
        team: 'red', col: 2, row: 3, cellSize: 32, realtime: RealtimeStats(speed: 3, attackInterval: 0.5));
    final turn = spawnStrategyUnit(w, team: 'red', col: 3, row: 3, cellSize: 32);
    expect(w.storeOf<RealtimeStats>().get(u)!.speed, 3);
    expect(w.storeOf<ActionPoints>().has(u), isFalse);
    expect(w.storeOf<ActionPoints>().has(turn), isTrue);
    expect(w.storeOf<RealtimeStats>().has(turn), isFalse);
  });

  test('a whole real-time skirmish: tap to select, tap to attack-move, win', () {
    final w = _world();
    final install = installRealtimeStrategySystems(w, navigator: _nav(), cellSize: 32);
    final squad = [
      for (var i = 0; i < 4; i++)
        spawnStrategyUnit(w,
            team: 'red',
            col: 1,
            row: 4 + i,
            cellSize: 32,
            attack: 6,
            realtime: RealtimeStats(speed: 5, attackInterval: 0.5)),
    ];
    final foe = spawnStrategyUnit(w,
        team: 'blue', col: 12, row: 6, cellSize: 32, maxHp: 20, realtime: RealtimeStats(speed: 2));
    final victories = <VictoryEvent>[];
    w.events.on<VictoryEvent>(victories.add);

    final taps = GridTapController(32, localTeam: 'red');
    expect(taps.handleDrag(w, const Offset(0, 4 * 32), const Offset(64, 8 * 32)), 4);
    expect(taps.handleTap(w, Offset(12.5 * 32, 6.5 * 32)), GridTapResult.commanded);

    for (var i = 0; i < 400 && install.matchRule.winner == null; i++) {
      w.step(1 / 20);
    }
    expect(w.entities.isAlive(foe), isFalse);
    expect(install.matchRule.winner, 'red');
    expect(victories.single.team, 'red');
    expect(squad.where(w.entities.isAlive), isNotEmpty);
    expect(install.fields.builds, lessThan(40), reason: 'shared fields, not one search per unit per tick');
  });

  test('positions follow the grid so rendering tracks movement', () {
    final w = _world();
    installRealtimeStrategySystems(w, navigator: _nav(), cellSize: 32);
    final u = spawnStrategyUnit(w,
        team: 'red', col: 0, row: 0, cellSize: 32, realtime: RealtimeStats(speed: 10));
    spawnStrategyUnit(w, team: 'blue', col: 19, row: 19, cellSize: 32, realtime: RealtimeStats(speed: 1));
    submitOrder(w, u, const MoveOrder(5, 0));
    for (var i = 0; i < 20; i++) {
      w.step(1 / 20);
    }
    final p = w.storeOf<Position>().get(u)!;
    expect((p.x, p.y), (5.5 * 32, 0.5 * 32));
  });
}
