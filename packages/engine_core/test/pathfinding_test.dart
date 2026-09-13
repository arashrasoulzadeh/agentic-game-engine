import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('findPath', () {
    test('an empty grid finds a straight path from start to goal', () {
      final map = TileMap(
        cols: 5,
        rows: 1,
        tileWidth: 40,
        tileHeight: 40,
        tiles: List.filled(5, 0),
      );
      final path = findPath(map, Position(0, 0), 20, 20, 180, 20); // col 0 -> col 4

      expect(path, isNotEmpty);
      expect(path.last.x, closeTo(180, 1e-9));
      // Each step moves exactly one tile.
      expect(path.length, 4);
    });

    test('routes around a wall blocking the direct path', () {
      // 3x3 grid; middle row's middle cell is a solid wall, so the
      // path from (0,1) to (2,1) has to detour through row 0 or row 2.
      final map = TileMap(
        cols: 3,
        rows: 3,
        tileWidth: 40,
        tileHeight: 40,
        tiles: [
          0, 0, 0,
          0, 1, 0,
          0, 0, 0,
        ],
        solidTileIds: {1},
      );
      final path = findPath(map, Position(0, 0), 20, 60, 100, 60); // (col0,row1) -> (col2,row1)

      expect(path, isNotEmpty);
      // Never passes through the blocked cell (col1,row1 center = 60,60).
      expect(path.any((p) => p.x == 60 && p.y == 60), isFalse);
      expect(path.last.x, closeTo(100, 1e-9));
      expect(path.last.y, closeTo(60, 1e-9));
    });

    test('returns empty when the goal is unreachable (fully walled off)', () {
      final map = TileMap(
        cols: 3,
        rows: 1,
        tileWidth: 40,
        tileHeight: 40,
        tiles: [0, 1, 0],
        solidTileIds: {1},
      );
      final path = findPath(map, Position(0, 0), 20, 20, 100, 20); // col 0 -> col 2, wall at col 1

      expect(path, isEmpty);
    });

    test('returns empty when the goal cell is itself solid', () {
      final map = TileMap(
        cols: 2,
        rows: 1,
        tileWidth: 40,
        tileHeight: 40,
        tiles: [0, 1],
        solidTileIds: {1},
      );
      final path = findPath(map, Position(0, 0), 20, 20, 60, 20);

      expect(path, isEmpty);
    });

    test('returns empty when start and goal are already the same cell', () {
      final map = TileMap(cols: 2, rows: 1, tileWidth: 40, tileHeight: 40, tiles: [0, 0]);
      final path = findPath(map, Position(0, 0), 10, 20, 30, 20); // both in col 0

      expect(path, isEmpty);
    });

    test('one-way and slope tiles are walkable, not walls', () {
      final map = TileMap(
        cols: 3,
        rows: 1,
        tileWidth: 40,
        tileHeight: 40,
        tiles: [0, 2, 0],
        oneWayTileIds: {2},
      );
      final path = findPath(map, Position(0, 0), 20, 20, 100, 20);

      expect(path, isNotEmpty);
      expect(path.length, 2); // straight through the one-way tile
    });

    test('respects a non-zero TileMap origin', () {
      final map = TileMap(cols: 3, rows: 1, tileWidth: 40, tileHeight: 40, tiles: [0, 0, 0]);
      final origin = Position(1000, 1000);
      final path = findPath(map, origin, 1020, 1020, 1100, 1020);

      expect(path, isNotEmpty);
      expect(path.last.x, closeTo(1100, 1e-9));
    });

    test('finds the shortest path through a larger maze (exercises many open-set operations)', () {
      // 20x20 grid with a maze-like wall pattern -- enough nodes that
      // this exercises many add/removeMin cycles on the open-set heap,
      // including nodes getting pushed more than once as cheaper
      // routes to them are found (no decrease-key -- see findPath's
      // doc comment), not just the handful of cells the smaller tests
      // above touch.
      const size = 20;
      final tiles = List.filled(size * size, 0);
      // A wall down most of column 10, with a single gap at row 15 --
      // forces a real detour, not just a straight line.
      for (var row = 0; row < size; row++) {
        if (row != 15) tiles[row * size + 10] = 1;
      }
      final map = TileMap(cols: size, rows: size, tileWidth: 10, tileHeight: 10, tiles: tiles, solidTileIds: {1});

      final path = findPath(map, Position(0, 0), 5, 5, 195, 195); // (0,0) -> (19,19)

      expect(path, isNotEmpty);
      expect(path.last.x, closeTo(195, 1e-9));
      expect(path.last.y, closeTo(195, 1e-9));
      // Must actually go through the gap at row 15, not through any
      // other cell in the column-10 wall.
      expect(path.any((p) => p.x == 105 && p.y == 155), isTrue);
      for (var row = 0; row < size; row++) {
        if (row == 15) continue;
        expect(path.any((p) => p.x == 105 && p.y == row * 10 + 5), isFalse);
      }
      // The gap at (col 10, row 15) is a mandatory waypoint, so the
      // true shortest path length is the Manhattan distance from start
      // to that gap plus gap to goal, regardless of the exact route
      // taken to get there: (10+15) + (9+4) = 38.
      expect(path.length, 38);
    });
  });

  group('WorldView.hasLineOfSight', () {
    World buildWorld() {
      final world = World(width: 400, height: 400);
      registerCoreComponents(world);
      return world;
    }

    test('true when nothing blocks the line', () {
      final world = buildWorld();
      final view = WorldView(world);
      expect(view.hasLineOfSight(0, 20, 200, 20), isTrue);
    });

    test('false when a solid tile blocks the line', () {
      final world = buildWorld();
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 3,
              rows: 1,
              tileWidth: 40,
              tileHeight: 40,
              tiles: [0, 1, 0],
              solidTileIds: {1},
            ),
          );

      final view = WorldView(world);
      expect(view.hasLineOfSight(0, 20, 120, 20), isFalse);
    });

    test('true through a one-way tile by default', () {
      final world = buildWorld();
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 3,
              rows: 1,
              tileWidth: 40,
              tileHeight: 40,
              tiles: [0, 2, 0],
              oneWayTileIds: {2},
            ),
          );

      final view = WorldView(world);
      expect(view.hasLineOfSight(0, 20, 120, 20), isTrue);
    });
  });
}
