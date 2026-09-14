import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('constructor rejects a tiles list of the wrong length', () {
    expect(
      () => TileMap(cols: 2, rows: 2, tileWidth: 10, tileHeight: 10, tiles: [0, 0, 0]),
      throwsArgumentError,
    );
  });

  test('tileAt is bounds-checked and returns 0 outside the grid', () {
    final map = TileMap(
      cols: 2,
      rows: 2,
      tileWidth: 10,
      tileHeight: 10,
      tiles: [1, 2, 3, 4],
    );

    expect(map.tileAt(0, 0), 1);
    expect(map.tileAt(1, 1), 4);
    expect(map.tileAt(-1, 0), 0);
    expect(map.tileAt(0, -1), 0);
    expect(map.tileAt(2, 0), 0);
    expect(map.tileAt(0, 2), 0);
  });

  test('isSolid/isOneWay check tileAt against the configured id sets', () {
    final map = TileMap(
      cols: 2,
      rows: 1,
      tileWidth: 10,
      tileHeight: 10,
      tiles: [1, 2],
      solidTileIds: {1},
      oneWayTileIds: {2},
    );

    expect(map.isSolid(0, 0), isTrue);
    expect(map.isOneWay(0, 0), isFalse);
    expect(map.isSolid(1, 0), isFalse);
    expect(map.isOneWay(1, 0), isTrue);
  });

  test('TileMap round-trips through toJson/fromJson', () {
    final map = TileMap(
      cols: 2,
      rows: 2,
      tileWidth: 16,
      tileHeight: 16,
      tiles: [0, 1, 2, 0],
      solidTileIds: {1},
      oneWayTileIds: {2},
    );

    final decoded = TileMap.fromJson(map.toJson());
    expect(decoded.cols, 2);
    expect(decoded.rows, 2);
    expect(decoded.tileWidth, 16);
    expect(decoded.tileHeight, 16);
    expect(decoded.tiles, [0, 1, 2, 0]);
    expect(decoded.solidTileIds, {1});
    expect(decoded.oneWayTileIds, {2});
  });

  test('TileMap.fromJson defaults solid/oneWay id sets to empty when absent', () {
    final decoded = TileMap.fromJson({
      'cols': 1,
      'rows': 1,
      'tileWidth': 10,
      'tileHeight': 10,
      'tiles': [0],
    });

    expect(decoded.solidTileIds, isEmpty);
    expect(decoded.oneWayTileIds, isEmpty);
  });

  test('TileMap.fromJson accepts a legend + ASCII rows instead of a flat tiles array', () {
    final decoded = TileMap.fromJson({
      'tileWidth': 10,
      'tileHeight': 10,
      'legend': {'.': 0, '#': 1, '=': 2},
      'rows': [
        '..=..',
        '.....',
        '##.##',
      ],
      'solidTileIds': [1],
      'oneWayTileIds': [2],
    });

    expect(decoded.cols, 5);
    expect(decoded.rows, 3);
    expect(decoded.tileAt(2, 0), 2);
    expect(decoded.tileAt(0, 2), 1);
    expect(decoded.tileAt(2, 2), 0);
    expect(decoded.isSolid(0, 2), isTrue);
    expect(decoded.isOneWay(2, 0), isTrue);
  });

  test('TileMap.fromJson legend form rejects a row of the wrong width', () {
    expect(
      () => TileMap.fromJson({
        'tileWidth': 10,
        'tileHeight': 10,
        'legend': {'.': 0},
        'rows': ['...', '..'],
      }),
      throwsArgumentError,
    );
  });

  test('isSlopeUpRight/isSlopeUpLeft check tileAt against the configured id sets', () {
    final map = TileMap(
      cols: 2,
      rows: 1,
      tileWidth: 10,
      tileHeight: 10,
      tiles: [3, 4],
      slopeUpRightTileIds: {3},
      slopeUpLeftTileIds: {4},
    );

    expect(map.isSlopeUpRight(0, 0), isTrue);
    expect(map.isSlopeUpLeft(0, 0), isFalse);
    expect(map.isSlopeUpRight(1, 0), isFalse);
    expect(map.isSlopeUpLeft(1, 0), isTrue);
  });

  test('slope tile ids round-trip through toJson/fromJson', () {
    final map = TileMap(
      cols: 2,
      rows: 1,
      tileWidth: 10,
      tileHeight: 10,
      tiles: [3, 4],
      slopeUpRightTileIds: {3},
      slopeUpLeftTileIds: {4},
    );

    final decoded = TileMap.fromJson(map.toJson());
    expect(decoded.slopeUpRightTileIds, {3});
    expect(decoded.slopeUpLeftTileIds, {4});
  });

  test('ladder/conveyor/friction tile data round-trips through toJson/fromJson', () {
    final map = TileMap(
      cols: 3,
      rows: 1,
      tileWidth: 10,
      tileHeight: 10,
      tiles: [5, 6, 7],
      ladderTileIds: {5},
      conveyorSpeedByTileId: {6: 80.0},
      frictionByTileId: {7: 0.2},
    );

    expect(map.isLadder(0, 0), isTrue);
    expect(map.isLadder(1, 0), isFalse);

    final decoded = TileMap.fromJson(map.toJson());
    expect(decoded.ladderTileIds, {5});
    expect(decoded.conveyorSpeedByTileId, {6: 80.0});
    expect(decoded.frictionByTileId, {7: 0.2});
  });

  test('ladder/conveyor/friction default to empty when unset', () {
    final map = TileMap(cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1]);
    expect(map.ladderTileIds, isEmpty);
    expect(map.conveyorSpeedByTileId, isEmpty);
    expect(map.frictionByTileId, isEmpty);
  });

  test('atlasId/regionByTileId round-trip through toJson/fromJson', () {
    final map = TileMap(
      cols: 2,
      rows: 1,
      tileWidth: 10,
      tileHeight: 10,
      tiles: [1, 2],
      atlasId: 'tileset',
      regionByTileId: {1: 'grass', 2: 'dirt'},
    );

    final decoded = TileMap.fromJson(map.toJson());
    expect(decoded.atlasId, 'tileset');
    expect(decoded.regionByTileId, {1: 'grass', 2: 'dirt'});
  });

  test('atlasId/regionByTileId default to null/empty when unset, and atlasId is '
      'omitted from toJson entirely rather than serialized as null', () {
    final map = TileMap(cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1]);
    expect(map.atlasId, isNull);
    expect(map.regionByTileId, isEmpty);
    expect(map.toJson().containsKey('atlasId'), isFalse);

    final decoded = TileMap.fromJson(map.toJson());
    expect(decoded.atlasId, isNull);
    expect(decoded.regionByTileId, isEmpty);
  });

  test('TileMap.fromJson legend form rejects a character missing from the legend', () {
    expect(
      () => TileMap.fromJson({
        'tileWidth': 10,
        'tileHeight': 10,
        'legend': {'.': 0},
        'rows': ['.#.'],
      }),
      throwsArgumentError,
    );
  });

  group('backgroundTiles/foregroundTiles', () {
    test('null by default, and bounds-checked accessors return 0', () {
      final map = TileMap(cols: 2, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [0, 0]);
      expect(map.backgroundTiles, isNull);
      expect(map.foregroundTiles, isNull);
      expect(map.backgroundTileAt(0, 0), 0);
      expect(map.foregroundTileAt(0, 0), 0);
      expect(map.backgroundTileAt(5, 5), 0, reason: 'out of bounds, still safe');
    });

    test('constructor rejects a backgroundTiles/foregroundTiles list of the wrong length', () {
      expect(
        () => TileMap(
            cols: 2, rows: 2, tileWidth: 10, tileHeight: 10,
            tiles: [0, 0, 0, 0], backgroundTiles: [1, 1]),
        throwsArgumentError,
      );
      expect(
        () => TileMap(
            cols: 2, rows: 2, tileWidth: 10, tileHeight: 10,
            tiles: [0, 0, 0, 0], foregroundTiles: [1, 1]),
        throwsArgumentError,
      );
    });

    test('backgroundTileAt/foregroundTileAt read their own grid, independent of tiles', () {
      final map = TileMap(
        cols: 2,
        rows: 1,
        tileWidth: 10,
        tileHeight: 10,
        tiles: [5, 6],
        backgroundTiles: [1, 2],
        foregroundTiles: [3, 4],
      );
      expect(map.backgroundTileAt(0, 0), 1);
      expect(map.backgroundTileAt(1, 0), 2);
      expect(map.foregroundTileAt(0, 0), 3);
      expect(map.foregroundTileAt(1, 0), 4);
      expect(map.tileAt(0, 0), 5);
    });

    test('round-trip through toJson/fromJson, omitted from toJson when null', () {
      final withLayers = TileMap(
        cols: 2, rows: 1, tileWidth: 10, tileHeight: 10,
        tiles: [0, 0], backgroundTiles: [1, 1], foregroundTiles: [2, 2],
      );
      expect(withLayers.toJson()['backgroundTiles'], [1, 1]);
      final restored = TileMap.fromJson(withLayers.toJson());
      expect(restored.backgroundTiles, [1, 1]);
      expect(restored.foregroundTiles, [2, 2]);

      final withoutLayers = TileMap(cols: 2, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [0, 0]);
      expect(withoutLayers.toJson().containsKey('backgroundTiles'), isFalse);
      expect(withoutLayers.toJson().containsKey('foregroundTiles'), isFalse);
    });
  });

  group('tileAnimations / currentTileId', () {
    test('a tile id with no animation entry returns itself, unchanged over time', () {
      final map = TileMap(cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1]);
      expect(map.currentTileId(1), 1);
      map.animationElapsed = 10;
      expect(map.currentTileId(1), 1);
    });

    test('cycles through frames at tileAnimationFps, wrapping back to frame 0', () {
      final map = TileMap(
        cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1],
        tileAnimations: {1: [10, 11, 12]},
        tileAnimationFps: 2, // 0.5s per frame
      );

      map.animationElapsed = 0;
      expect(map.currentTileId(1), 10);
      map.animationElapsed = 0.6; // 1.2 frames in -> frame 1
      expect(map.currentTileId(1), 11);
      map.animationElapsed = 1.1; // 2.2 frames in -> frame 2
      expect(map.currentTileId(1), 12);
      map.animationElapsed = 1.6; // 3.2 frames in -> wraps to frame 0
      expect(map.currentTileId(1), 10);
    });

    test('animationElapsed is not serialized -- fresh on fromJson regardless of a live '
        'instance\'s state', () {
      final map = TileMap(cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1]);
      map.animationElapsed = 42;
      expect(map.toJson().containsKey('animationElapsed'), isFalse);
      expect(TileMap.fromJson(map.toJson()).animationElapsed, 0);
    });

    test('round-trips through toJson/fromJson, omitted from toJson when empty', () {
      final map = TileMap(
        cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1],
        tileAnimations: {1: [10, 11]},
        tileAnimationFps: 4,
      );
      expect(map.toJson()['tileAnimations'], {'1': [10, 11]});
      final restored = TileMap.fromJson(map.toJson());
      expect(restored.tileAnimations, {1: [10, 11]});
      expect(restored.tileAnimationFps, 4);

      final withoutAnimations = TileMap(cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1]);
      expect(withoutAnimations.toJson().containsKey('tileAnimations'), isFalse);
    });

    test('tileAnimationFps defaults to 6', () {
      expect(TileMap(cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [0]).tileAnimationFps, 6);
    });
  });

  group('TileAnimationSystem', () {
    test('advances animationElapsed on every TileMap by dt', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);
      world.addSystem(TileAnimationSystem());

      final id = world.spawn();
      final map = TileMap(cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [0]);
      world.storeOf<TileMap>().set(id, map);

      world.step(0.5);
      expect(map.animationElapsed, closeTo(0.5, 1e-9));
      world.step(0.25);
      expect(map.animationElapsed, closeTo(0.75, 1e-9));
    });
  });
}
