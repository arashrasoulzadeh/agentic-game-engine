import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('autotileBitmask', () {
    test('an isolated wall cell (no wall neighbors) is bitmask 0', () {
      final map = TileMap(cols: 3, rows: 3, tileWidth: 10, tileHeight: 10, tiles: [
        0, 0, 0, //
        0, 1, 0, //
        0, 0, 0, //
      ]);
      expect(autotileBitmask(map, 1, 1, {1}), 0);
    });

    test('a wall fully surrounded on all 4 sides is bitmask 15', () {
      final map = TileMap(cols: 3, rows: 3, tileWidth: 10, tileHeight: 10, tiles: [
        0, 1, 0, //
        1, 1, 1, //
        0, 1, 0, //
      ]);
      expect(autotileBitmask(map, 1, 1, {1}), 1 | 2 | 4 | 8);
    });

    test('bit assignment is north=1, east=2, south=4, west=8', () {
      final map = TileMap(cols: 3, rows: 3, tileWidth: 10, tileHeight: 10, tiles: [
        0, 1, 0, //
        0, 1, 0, //
        0, 0, 0, //
      ]);
      // Only the north neighbor is a wall.
      expect(autotileBitmask(map, 1, 1, {1}), 1);
    });

    test('a neighbor off the grid edge counts as not-a-wall, no wraparound', () {
      final map = TileMap(cols: 2, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1, 1]);
      // Cell (0,0)'s west neighbor is off-grid; its east neighbor (1,0) is
      // a wall. If edges wrapped, west would incorrectly pick up tile (1,0).
      expect(autotileBitmask(map, 0, 0, {1}), 2);
    });

    test('wallTileIds can include ids other than the cell itself', () {
      final map = TileMap(cols: 3, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [2, 1, 3]);
      expect(autotileBitmask(map, 1, 0, {1, 2, 3}), 2 | 8);
      expect(autotileBitmask(map, 1, 0, {1}), 0);
    });
  });

  test('autotileRegionName joins base name and bitmask with an underscore', () {
    expect(autotileRegionName('wall', 13), 'wall_13');
    expect(autotileRegionName('wall', 0), 'wall_0');
  });

  test('autotileSyntheticId is distinct per base tile id and bitmask', () {
    final ids = <int>{};
    for (final base in [1, 2]) {
      for (var bitmask = 0; bitmask < 16; bitmask++) {
        ids.add(autotileSyntheticId(base, bitmask));
      }
    }
    expect(ids, hasLength(32), reason: 'every (baseTileId, bitmask) pair must be unique');
  });

  group('TileMap.withAutotile', () {
    test('replaces each wall cell with a synthetic id carrying its bitmask region', () {
      final map = TileMap(cols: 3, rows: 3, tileWidth: 10, tileHeight: 10, tiles: [
        0, 1, 0, //
        1, 1, 1, //
        0, 1, 0, //
      ]);

      final resolved = map.withAutotile(baseTileId: 1, regionPrefix: 'wall');

      final centerId = resolved.tileAt(1, 1);
      expect(centerId, autotileSyntheticId(1, 15));
      expect(resolved.regionByTileId[centerId], 'wall_15');

      final topId = resolved.tileAt(1, 0);
      expect(topId, autotileSyntheticId(1, 4), reason: 'only its south neighbor is a wall');
      expect(resolved.regionByTileId[topId], 'wall_4');
    });

    test('empty cells (not baseTileId) are left completely untouched', () {
      final map = TileMap(cols: 2, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [0, 1]);
      final resolved = map.withAutotile(baseTileId: 1, regionPrefix: 'wall');
      expect(resolved.tileAt(0, 0), 0);
    });

    test('collision membership carries over to every synthetic variant actually used', () {
      final map = TileMap(
        cols: 2,
        rows: 1,
        tileWidth: 10,
        tileHeight: 10,
        tiles: [1, 1],
        solidTileIds: {1},
      );

      final resolved = map.withAutotile(baseTileId: 1, regionPrefix: 'wall');

      expect(resolved.isSolid(0, 0), isTrue);
      expect(resolved.isSolid(1, 0), isTrue);
      // The original base id is no longer present in the grid, but it's
      // harmless for it to remain in solidTileIds -- nothing looks it up
      // by that id anymore since every cell now holds a synthetic id.
    });

    test('conveyor/friction per-tile values carry over to synthetic variants', () {
      final map = TileMap(
        cols: 1,
        rows: 1,
        tileWidth: 10,
        tileHeight: 10,
        tiles: [1],
        conveyorSpeedByTileId: {1: 50.0},
        frictionByTileId: {1: 0.2},
      );

      final resolved = map.withAutotile(baseTileId: 1, regionPrefix: 'ice');
      final id = resolved.tileAt(0, 0);

      expect(resolved.conveyorSpeedByTileId[id], 50.0);
      expect(resolved.frictionByTileId[id], 0.2);
    });

    test('an explicit wallTileIds lets multiple wall tile types connect to each other', () {
      final map = TileMap(cols: 3, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [2, 1, 3]);
      final resolved =
          map.withAutotile(baseTileId: 1, regionPrefix: 'wall', wallTileIds: {1, 2, 3});
      final id = resolved.tileAt(1, 0);
      expect(id, autotileSyntheticId(1, 2 | 8), reason: 'both east and west neighbors count as walls');
    });

    test('round-trips through toJson/fromJson like any other TileMap', () {
      final map = TileMap(cols: 2, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1, 1]);
      final resolved = map.withAutotile(baseTileId: 1, regionPrefix: 'wall');
      final restored = TileMap.fromJson(resolved.toJson());
      expect(restored.tiles, resolved.tiles);
      expect(restored.regionByTileId, resolved.regionByTileId);
    });
  });
}
