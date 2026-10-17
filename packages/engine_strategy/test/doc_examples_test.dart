// Every code sample in docs/tutorials/02-turn-based-strategy.md and the
// turn-based recipes under docs/examples/ is exercised here, so the docs
// can't drift from the API without this file failing. Keep the two in sync.
import 'dart:ui';

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_strategy/engine_strategy.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

World newWorld() {
  final world = World(width: 384, height: 384);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

void main() {
  group('tutorial 02', () {
    test('steps 1-5: install, spawn, start, tap, resolve', () {
      // Step 1 -- a world and a grid.
      final world = newWorld();
      const cell = 48.0;
      final nav = GridNavigator(cols: 8, rows: 8, terrainCost: (col, row) => 1);

      // Step 2 -- install the systems.
      installStrategySystems(world, navigator: nav, cellSize: cell);

      // Step 3 -- spawn two armies.
      final knight = spawnStrategyUnit(world,
          team: 'red', col: 1, row: 6, cellSize: cell, maxHp: 12, attack: 5, actionPoints: 4);
      final archer = spawnStrategyUnit(world,
          team: 'red', col: 2, row: 6, cellSize: cell, attack: 3, actionPoints: 3);
      final goblin = spawnStrategyUnit(world,
          team: 'blue', col: 5, row: 2, cellSize: cell, maxHp: 8, attack: 2);

      // Step 4 -- start the clock *after* the units exist.
      startTurnBasedGame(world, ['red', 'blue']);
      expect(turnStateOf(world)!.activeTeam, 'red');
      expect(world.storeOf<ActionPoints>().get(knight)!.current, 4);

      // Step 5 -- feed taps through a GridTapController.
      final taps = GridTapController(cell);
      expect(taps.handleTap(world, const Offset(1.5 * cell, 6.5 * cell)), GridTapResult.selected);
      expect(taps.handleTap(world, const Offset(1.5 * cell, 4.5 * cell)), GridTapResult.commanded);
      world.step(1 / 60);
      expect(world.storeOf<GridPosition>().get(knight)!.row, 4);
      expect(world.storeOf<ActionPoints>().get(knight)!.current, 2);

      // Attack by tapping the enemy: the unit walks into range first.
      taps.handleTap(world, const Offset(5.5 * cell, 2.5 * cell));
      world.step(1 / 60);
      expect(world.storeOf<OrderQueue>().get(knight)!.orders, isNotEmpty);

      endTurn(world);
      expect(turnStateOf(world)!.activeTeam, 'blue');
      expect(world.storeOf<UnitStats>().get(goblin)!.hp, 8);
      expect(world.entities.isAlive(archer), isTrue);
    });

    test('step 6: terrain from a TileMap', () {
      const forest = 2, mountain = 3;
      final map = TileMap(
        cols: 5,
        rows: 1,
        tileWidth: 48,
        tileHeight: 48,
        tiles: [0, forest, forest, mountain, 0],
        solidTileIds: {mountain},
      );
      final nav = GridNavigator.fromTileMap(map, terrainCosts: {forest: 3});

      expect(nav.terrainCost(0, 0), 1);
      expect(nav.terrainCost(1, 0), 3);
      expect(nav.terrainCost(3, 0), isNull); // mountains are walls

      final reach = nav.reachable(GridPosition(0, 0), 4);
      expect(reach[(1, 0)], 3);
      expect(reach.containsKey((2, 0)), isFalse); // 3 + 3 > 4
    });

    test('step 7-9: AI opponent, events, victory', () {
      final world = newWorld();
      const cell = 48.0;
      installStrategySystems(
        world,
        navigator: GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1),
        cellSize: cell,
        aiTeams: {'blue': AggressiveAI()},
      );
      final hero = spawnStrategyUnit(world,
          team: 'red', col: 0, row: 0, cellSize: cell, maxHp: 30, attack: 6);
      final orc = spawnStrategyUnit(world,
          team: 'blue', col: 3, row: 0, cellSize: cell, maxHp: 10, attack: 2);

      final log = <String>[];
      world.events.on<UnitDamagedEvent>((e) => log.add('hit ${e.target} for ${e.amount}'));
      world.events.on<VictoryEvent>((e) => log.add('${e.team} wins'));
      startTurnBasedGame(world, ['red', 'blue']);

      // One loop iteration = red orders and passes, then blue's AI plays.
      for (var round = 0; round < 10 && turnStateOf(world)!.winner == null; round++) {
        submitOrder(world, hero, AttackOrder(orc));
        world.step(1 / 60); // orders execute
        endTurn(world);
        for (var i = 0; i < 4; i++) {
          world.step(1 / 60); // AI plans, acts, hands the turn back
        }
      }
      expect(turnStateOf(world)!.winner, 'red');
      expect(log.last, 'red wins');
    });
  });

  group('recipes', () {
    test('fog of war with walls', () {
      final world = newWorld();
      final walls = {(4, 3)};
      final fogEntity = installStrategySystems(
        world,
        navigator: GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1),
        cellSize: 48,
        fog: true,
        blocksSight: (col, row) => walls.contains((col, row)),
      )!;
      final scout = spawnStrategyUnit(world,
          team: 'red', col: 2, row: 3, cellSize: 48, visionRange: 4);
      final spy = spawnStrategyUnit(world, team: 'blue', col: 6, row: 3, cellSize: 48);
      final near = spawnStrategyUnit(world, team: 'blue', col: 3, row: 3, cellSize: 48);
      startTurnBasedGame(world, ['red', 'blue']);
      world.step(1 / 60);

      final fog = world.storeOf<FogOfWar>().get(fogEntity)!;
      expect(fog.isVisible('red', 3, 3), isTrue);
      expect(fog.isVisible('red', 5, 3), isFalse); // behind the wall
      expect(canSee(world, 'red', near), isTrue);
      expect(canSee(world, 'red', spy), isFalse);
      expect(canSee(world, 'red', scout), isTrue); // own units are always known
      expect(fog.isExplored('red', 3, 3), isTrue);
    });

    test('move-range overlay', () {
      final nav = GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1);
      final cells = nav.reachable(GridPosition(3, 3), 2, blocked: (c, r) => c == 4 && r == 3);
      expect(cells.length, greaterThan(8));
      expect(cells.containsKey((4, 3)), isFalse); // occupied
      expect(cells[(5, 3)], 2); // walked around the blocker diagonally
      final rects = [
        for (final cell in cells.keys) Rect.fromLTWH(cell.$1 * 48.0, cell.$2 * 48.0, 48, 48),
      ];
      expect(rects.length, cells.length);
    });

    test('overlay painter draws without error and repaints on new cells', () {
      final nav = GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1);
      final cells = nav.reachable(GridPosition(3, 3), 2).keys;
      final painter = MoveRangePainter(cells, Camera(x: 192, y: 192));
      final recorder = PictureRecorder();
      painter.paint(Canvas(recorder), const Size(384, 384));
      recorder.endRecording();
      expect(painter.shouldRepaint(MoveRangePainter(cells, painter.camera)), isFalse);
      expect(painter.shouldRepaint(MoveRangePainter({(0, 0)}, painter.camera)), isTrue);
    });

    test('custom TurnAI: focus fire on the weakest visible enemy', () {
      final world = newWorld();
      installStrategySystems(
        world,
        navigator: GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1),
        cellSize: 48,
        aiTeams: {'blue': FocusFireAI()},
      );
      spawnStrategyUnit(world, team: 'red', col: 0, row: 0, cellSize: 48, maxHp: 20);
      final weak = spawnStrategyUnit(world, team: 'red', col: 0, row: 1, cellSize: 48, maxHp: 5);
      final bot = spawnStrategyUnit(world, team: 'blue', col: 1, row: 1, cellSize: 48, attack: 2);
      startTurnBasedGame(world, ['red', 'blue']);
      endTurn(world);
      world.step(1 / 60);
      expect((world.storeOf<OrderQueue>().get(bot)!.orders.single as AttackOrder).target, weak);
    });

    test('save and restore a turn-based game', () {
      final world = newWorld();
      installStrategySystems(world,
          navigator: GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1), cellSize: 48);
      spawnStrategyUnit(world, team: 'red', col: 1, row: 1, cellSize: 48);
      spawnStrategyUnit(world, team: 'blue', col: 5, row: 5, cellSize: 48);
      startTurnBasedGame(world, ['red', 'blue']);
      endTurn(world);

      final snapshot = world.toJson();

      // A fresh world needs the same entity ids alive before a patch applies.
      final restored = newWorld();
      for (final _ in world.entities.all) {
        restored.spawn();
      }
      restored.applyPatch(snapshot);
      expect(turnStateOf(restored)!.activeTeam, 'blue');
      expect(turnStateOf(restored)!.round, 1);
    });
  });
}

/// docs/examples/move-range-overlay.md
class MoveRangePainter extends CustomPainter {
  MoveRangePainter(this.cells, this.camera, {this.cellSize = 48});

  final Iterable<(int, int)> cells;
  final Camera camera;
  final double cellSize;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x5540E0D0);
    for (final (col, row) in cells) {
      final topLeft = camera.worldToScreen(col * cellSize, row * cellSize, size);
      final bottomRight = camera.worldToScreen((col + 1) * cellSize, (row + 1) * cellSize, size);
      canvas.drawRect(Rect.fromPoints(topLeft, bottomRight), fill);
    }
  }

  @override
  bool shouldRepaint(MoveRangePainter old) => old.cells != cells || old.camera != camera;
}

/// Targets the visible enemy with the fewest hit points.
class FocusFireAI implements TurnAI {
  @override
  void playTurn(World world, String team) {
    final teams = world.storeOf<Team>();
    final stats = world.storeOf<UnitStats>();
    EntityId? weakest;
    for (var i = 0; i < teams.length; i++) {
      final e = teams.entityAt(i);
      if (teams.denseAt(i).id == team || !canSee(world, team, e)) continue;
      final hp = stats.get(e)?.hp;
      if (hp == null) continue;
      if (weakest == null || hp < stats.get(weakest)!.hp) weakest = e;
    }
    if (weakest == null) return;
    for (var i = 0; i < teams.length; i++) {
      final unit = teams.entityAt(i);
      if (teams.denseAt(i).id != team) continue;
      submitOrder(world, unit, AttackOrder(weakest));
    }
  }
}
