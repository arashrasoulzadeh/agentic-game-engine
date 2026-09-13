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
}
