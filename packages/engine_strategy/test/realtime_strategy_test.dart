
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
  economyTests();
  test('registers the real-time systems in the documented order, with no turn systems', () {
    final w = _world();
    installRealtimeStrategySystems(w, navigator: _nav(), cellSize: 32);
    expect(w.systemOrder, ['realtimeOrders', 'lastTeamStanding', 'smoothGridToWorld', 'selectionMarkers']);

    final snapping = _world();
    installRealtimeStrategySystems(snapping, navigator: _nav(), cellSize: 32, smoothMotion: false);
    expect(snapping.systemOrder, ['realtimeOrders', 'lastTeamStanding', 'gridToWorld', 'selectionMarkers']);
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
    installRealtimeStrategySystems(w, navigator: _nav(), cellSize: 32, smoothMotion: false);
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

  group('SmoothGridToWorldSystem', () {
    World setup(void Function(World w) extra) {
      final w = _world();
      w.addSystem(SmoothGridToWorldSystem(32, cellsPerSecond: 4, snapDistanceCells: 3));
      extra(w);
      return w;
    }

    EntityId unit(World w, int col, int row) {
      final e = w.spawn();
      w.storeOf<GridPosition>().set(e, GridPosition(col, row));
      w.storeOf<Position>().set(e, Position((col + 0.5) * 32, (row + 0.5) * 32));
      return e;
    }

    test('glides toward the new cell at its speed instead of jumping', () {
      final w = setup((_) {});
      final u = unit(w, 0, 0);
      w.storeOf<GridPosition>().get(u)!.col = 2;
      w.step(0.1); // 4 cells/s * 0.1 s = 0.4 cell = 12.8 px
      final x = w.storeOf<Position>().get(u)!.x;
      expect(x, closeTo(16 + 12.8, 1e-9));
      expect(x, lessThan(2.5 * 32));
      for (var i = 0; i < 20; i++) {
        w.step(0.1);
      }
      expect(w.storeOf<Position>().get(u)!.x, 2.5 * 32);
    });

    test('never changes the grid cell: rules and networking still read GridPosition', () {
      final w = setup((_) {});
      final u = unit(w, 1, 1);
      w.storeOf<GridPosition>().get(u)!
        ..col = 3
        ..row = 2;
      w.step(0.05);
      final g = w.storeOf<GridPosition>().get(u)!;
      expect((g.col, g.row), (3, 2));
    });

    test('a far jump (respawn, snapshot restore) snaps rather than sliding across the map', () {
      final w = setup((_) {});
      final u = unit(w, 0, 0);
      w.storeOf<GridPosition>().get(u)!.col = 15;
      w.step(0.05);
      expect(w.storeOf<Position>().get(u)!.x, 15.5 * 32);
    });

    test('entities without a Position are left alone, and diagonal glides stay on the line', () {
      final w = setup((_) {});
      final bare = w.spawn();
      w.storeOf<GridPosition>().set(bare, GridPosition(4, 4));
      final u = unit(w, 0, 0);
      w.storeOf<GridPosition>().get(u)!
        ..col = 2
        ..row = 2;
      w.step(0.1);
      final p = w.storeOf<Position>().get(u)!;
      expect(p.x - 16, closeTo(p.y - 16, 1e-9), reason: 'moving along the diagonal');
      expect(w.storeOf<Position>().has(bare), isFalse);
    });
  });

  test('GridTapController with a formation navigator spreads a group order', () {
    final w = _world();
    installRealtimeStrategySystems(w, navigator: _nav(), cellSize: 32, selectionMarkers: false);
    final units = [
      for (var i = 0; i < 4; i++)
        spawnStrategyUnit(w, team: 'red', col: i, row: 0, cellSize: 32, realtime: RealtimeStats(speed: 6)),
    ];
    spawnStrategyUnit(w, team: 'blue', col: 19, row: 19, cellSize: 32, realtime: RealtimeStats(speed: 1));
    final taps = GridTapController(32, localTeam: 'red', formation: _nav());
    taps.handleDrag(w, const Offset(0, 0), const Offset(4 * 32, 16));
    taps.handleTap(w, Offset(10.5 * 32, 10.5 * 32));
    for (var i = 0; i < 200; i++) {
      w.step(1 / 20);
    }
    final cells = {for (final u in units) (w.storeOf<GridPosition>().get(u)!.col, w.storeOf<GridPosition>().get(u)!.row)};
    expect(cells, hasLength(4), reason: 'no two units ended on the same cell');
    for (final c in cells) {
      expect(GridPosition(c.$1, c.$2).chebyshev(GridPosition(10, 10)), lessThanOrEqualTo(1));
    }
  });
}

void economyTests() {
  test('production: true wires income and Producer buildings into the real-time game', () {
    final w = _world();
    installRealtimeStrategySystems(w, navigator: _nav(), cellSize: 32, production: true);
    expect(w.systemOrder.first, 'production');

    w.storeOf<Treasury>().set(w.spawn(), Treasury('red', amounts: {'gold': 50}, incomePerSecond: {'gold': 1}));
    final barracks = w.spawn();
    w.storeOf<Team>().set(barracks, Team('red'));
    w.storeOf<GridPosition>().set(barracks, GridPosition(3, 3));
    w.storeOf<Producer>().set(
          barracks,
          Producer(cost: {'gold': 30}, seconds: 1, template: {
            'unitStats': {'maxHp': 8, 'hp': 8, 'attack': 2, 'defense': 0},
            'realtimeStats': {'speed': 3.0, 'attackInterval': 1.0},
          }),
        );
    queueProduction(w, barracks);
    for (var i = 0; i < 40; i++) {
      w.step(1 / 20);
    }
    expect(w.storeOf<RealtimeStats>().length, 1);
    final gold = w.storeOf<Treasury>().denseAt(0).of('gold');
    expect(gold, inInclusiveRange(20, 24), reason: '50 - 30 spent + about 2 s of income');
  });

  test('without production: true there is no economy system', () {
    final w = _world();
    installRealtimeStrategySystems(w, navigator: _nav(), cellSize: 32);
    expect(w.systemOrder.contains('production'), isFalse);
  });

  test('aiTeams adds the real-time AI before the orders so its commands run the same tick', () {
    final w = _world();
    installRealtimeStrategySystems(w,
        navigator: _nav(), cellSize: 32, aiTeams: {'blue': AggressiveAI()}, production: true);
    expect(w.systemOrder.indexOf('production'), lessThan(w.systemOrder.indexOf('realtimeAi')));
    expect(w.systemOrder.indexOf('realtimeAi'), lessThan(w.systemOrder.indexOf('realtimeOrders')));
  });
}
