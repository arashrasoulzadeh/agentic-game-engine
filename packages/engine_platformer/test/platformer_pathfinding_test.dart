import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:engine_core/src/physics/pathfinding.dart' show PathPoint;

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerPlatformerComponents(world);
  return world;
}

TileMap _createMap(World world, {
  required List<List<int>> grid,
  double tileSize = 40,
  Set<int> solidTiles = const {1},
  Set<int> oneWayTiles = const {2},
  Set<int> ladderTiles = const {3},
}) {
  final mapEntity = world.spawn();
  final rows = grid.length;
  final cols = grid[0].length;
  final tiles = <int>[];
  for (final row in grid) {
    tiles.addAll(row);
  }
  world.storeOf<Position>().set(mapEntity, Position(0, 0));
  world.storeOf<TileMap>().set(mapEntity, TileMap(
    cols: cols,
    rows: rows,
    tileWidth: tileSize,
    tileHeight: tileSize,
    tiles: tiles,
    solidTileIds: solidTiles,
    oneWayTileIds: oneWayTiles,
  ));
  return world.storeOf<TileMap>().get(mapEntity)!;
}

void main() {
  group('PlatformerPathfinder', () {
    test('finds horizontal path on flat ground', () {
      final world = _buildWorld();
      // 20x10 grid, row 9 is solid floor
      final grid = List.generate(10, (r) => List.filled(20, 0));
      for (int c = 0; c < 20; c++) grid[9][c] = 1;
      final map = _createMap(world, grid: grid);

      final path = world.findPlatformerPath(
        map: map,
        origin: Position(0, 0),
        fromX: 40, fromY: 340, // tile (1, 8) - standing on floor at row 9
        toX: 600, toY: 340,    // tile (15, 8) - standing on floor at row 9
        ladderTileIds: const {},
        oneWayTileIds: const {},
        config: PlatformerPathfinderConfig(maxJumpHorizontalTiles: 0), // Disable jumping
      );

      expect(path, isNotEmpty);
      expect(path.length, greaterThan(10));
      for (final p in path) {
        expect(p.jumpRequired, isFalse);
        expect(p.climbRequired, isFalse);
      }
    });

    test('finds path requiring jump over gap', () {
      final world = _buildWorld();
      // Floor with gap at tiles 5-9
      final grid = List.generate(10, (r) => List.filled(20, 0));
      for (int c = 0; c < 20; c++) {
        if (c < 5 || c >= 10) grid[9][c] = 1;
      }
      final map = _createMap(world, grid: grid);

      final path = world.findPlatformerPath(
        map: map,
        origin: Position(0, 0),
        fromX: 40, fromY: 340, // left of gap (standing on floor row 9)
        toX: 600, toY: 340,    // right of gap (standing on floor row 9)
        ladderTileIds: const {},
        oneWayTileIds: const {},
        config: PlatformerPathfinderConfig(maxJumpHorizontalTiles: 6),
      );

      expect(path, isNotEmpty);
      // Should have at least one jump
      final hasJump = path.any((p) => p.jumpRequired);
      expect(hasJump, isTrue, reason: 'path should require jump over gap');
    });

    test('finds path over one-way platform', () {
      final world = _buildWorld();
      // Solid floor at row 9, one-way platform at row 7 spanning gap
      final grid = List.generate(10, (r) => List.filled(20, 0));
      for (int c = 0; c < 20; c++) {
        grid[9][c] = 1; // solid floor
        if (c >= 5 && c < 15) grid[7][c] = 2; // one-way platform
      }
      final map = _createMap(world, grid: grid, oneWayTiles: {2});

      final path = world.findPlatformerPath(
        map: map,
        origin: Position(0, 0),
        fromX: 40, fromY: 340, // on solid floor (row 8, above floor at row 9)
        toX: 200, toY: 280,  // on one-way platform (row 7)
        ladderTileIds: const {},
        oneWayTileIds: {2},
        config: PlatformerPathfinderConfig(maxJumpHorizontalTiles: 6, maxJumpHeightTiles: 4),
      );

      expect(path, isNotEmpty);
      // Should reach the one-way platform
      final lastPoint = path.last;
      expect(lastPoint.y, lessThan(320), reason: 'should reach elevated platform');
    });

    test('finds path using ladder', () {
      final world = _buildWorld();
      // Vertical shaft with ladder at col 10
      final grid = List.generate(10, (r) => List.filled(20, 0));
      for (int c = 0; c < 20; c++) grid[9][c] = 1; // floor
      for (int r = 0; r < 10; r++) grid[r][10] = 3; // ladder
      final map = _createMap(world, grid: grid, ladderTiles: {3});

      final path = world.findPlatformerPath(
        map: map,
        origin: Position(0, 0),
        fromX: 420, fromY: 340, // bottom of ladder (standing on floor at row 9)
        toX: 420, toY: 40,      // top of ladder (row 0)
        ladderTileIds: {3},
        oneWayTileIds: const {},
      );

      expect(path, isNotEmpty);
      // Should have climb points
      final hasClimb = path.any((p) => p.climbRequired);
      expect(hasClimb, isTrue, reason: 'path should use ladder climbing');
    });

test('finds path dropping down from ledge', () {
      final world = _buildWorld();
      // Two levels: upper at row 5 (with gap at col 10), lower at row 9
      final grid = List.generate(10, (r) => List.filled(20, 0));
      for (int c = 0; c < 20; c++) {
        grid[9][c] = 1;  // lower floor (full width)
        if (c != 10) grid[5][c] = 1;  // upper floor with gap at col 10
      }
      final map = _createMap(world, grid: grid);

      final path = world.findPlatformerPath(
        map: map,
        origin: Position(0, 0),
        fromX: 380, fromY: 180, // upper level left of gap (col 9, row 4 - standing on floor at row 5)
        toX: 420, toY: 340,     // lower level right of gap (col 10, row 8 - standing on floor at row 9)
        ladderTileIds: const {},
        oneWayTileIds: const {},
      );

      expect(path, isNotEmpty);
      // Should have fall points
      final hasFall = path.any((p) => p.fallRequired);
      expect(hasFall, isTrue, reason: 'path should drop down');
    });

    test('returns empty path when goal is inside solid', () {
      final world = _buildWorld();
      final grid = List.generate(10, (r) => List.filled(20, 0));
      for (int c = 0; c < 20; c++) grid[9][c] = 1;
      final map = _createMap(world, grid: grid);

      final path = world.findPlatformerPath(
        map: map,
        origin: Position(0, 0),
        fromX: 40, fromY: 340,
        toX: 40, toY: 380, // inside solid floor (row 9 spans 360-400)
        ladderTileIds: const {},
        oneWayTileIds: const {},
      );

      expect(path, isEmpty);
    });

    test('returns empty path when no path exists', () {
      final world = _buildWorld();
      // Completely separated by wall
      final grid = List.generate(10, (r) => List.filled(20, 0));
      for (int r = 0; r < 10; r++) grid[r][10] = 1; // vertical wall
      final map = _createMap(world, grid: grid);

      final path = world.findPlatformerPath(
        map: map,
        origin: Position(0, 0),
        fromX: 40, fromY: 340,  // left of wall (standing on floor)
        toX: 600, toY: 340,     // right of wall (standing on floor)
        ladderTileIds: const {},
        oneWayTileIds: const {},
      );

      expect(path, isEmpty);
    });

test('can drop through one-way platform', () {
      final world = _buildWorld();
      // One-way platform at row 7, solid floor at row 9
      final grid = List.generate(10, (r) => List.filled(20, 0));
      for (int c = 0; c < 20; c++) {
        grid[9][c] = 1;  // solid floor
        grid[7][c] = 2;  // one-way platform
      }
      final map = _createMap(world, grid: grid, oneWayTiles: {2});

      final path = world.findPlatformerPath(
        map: map,
        origin: Position(0, 0),
        fromX: 400, fromY: 300, // on one-way platform (row 7)
        toX: 400, toY: 340,     // on solid floor below (row 8)
        ladderTileIds: const {},
        oneWayTileIds: {2},
      );

      expect(path, isNotEmpty);
      // Debug: print path points and their flags
      for (int i = 0; i < path.length; i++) {
        final p = path[i];
        print('Path[$i]: x=${p.x}, y=${p.y}, jump=${p.jumpRequired}, climb=${p.climbRequired}, fall=${p.fallRequired}, drop=${p.dropThroughOneWay}');
      }
      final hasDrop = path.any((p) => p.dropThroughOneWay);
      expect(hasDrop, isTrue, reason: 'should drop through one-way platform');
    });
  });
}