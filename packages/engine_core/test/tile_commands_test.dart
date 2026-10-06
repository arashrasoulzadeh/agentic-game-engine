import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// A legend-authored map, the same shape the default template uses.
LevelDocument _legendLevel() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'map',
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'tileMap': {
          'tileWidth': 10.0,
          'tileHeight': 10.0,
          'legend': {'.': 0, '#': 1},
          'rows': ['..#..', '..#..', '#####'],
        },
      },
    },
  ],
});

String _snapshot(LevelDocument doc) => jsonEncode(doc.toJson());

LevelEntity _map(LevelDocument doc) => doc.entities.single;

List<int> _flatTiles(LevelDocument doc) =>
    (_map(doc).components['tileMap']!['tiles'] as List).cast<int>();

void main() {
  group('FlattenTileMapCommand', () {
    test(
      'converts the legend to flat tile ids, and reverts to the legend exactly',
      () {
        final doc = _legendLevel();
        final before = _snapshot(doc);
        final command = FlattenTileMapCommand(_map(doc));

        command.apply(doc);
        expect(_map(doc).components['tileMap']!.containsKey('tiles'), isTrue);
        expect(_map(doc).components['tileMap']!.containsKey('legend'), isFalse);

        command.revert(doc);
        expect(_snapshot(doc), before);
      },
    );
  });

  group('SetTileCommand', () {
    test('paints a tile and reverts it to the previous id', () {
      final doc = _legendLevel();
      FlattenTileMapCommand(_map(doc)).apply(doc);
      final before = _snapshot(doc);

      final command = SetTileCommand(
        entity: _map(doc),
        col: 0,
        row: 0,
        tileId: 1,
      );
      command.apply(doc);
      expect(_flatTiles(doc).first, 1);

      command.revert(doc);
      expect(_snapshot(doc), before);
    });

    test('tile id 0 erases', () {
      final doc = _legendLevel();
      FlattenTileMapCommand(_map(doc)).apply(doc);
      // Column 2 of row 0 is solid (id 1) in the legend.
      SetTileCommand(entity: _map(doc), col: 2, row: 0, tileId: 0).apply(doc);
      expect(_flatTiles(doc)[2], 0);
    });
  });

  group('FillRegionCommand', () {
    test('fills the connected region of the same id, and reverts exactly', () {
      final doc = _legendLevel();
      FlattenTileMapCommand(_map(doc)).apply(doc);
      final before = _snapshot(doc);

      // The open area at the left, cols 0-1 of rows 0-1, is one connected region of 0s.
      final command = FillRegionCommand(
        entity: _map(doc),
        col: 0,
        row: 0,
        tileId: 7,
      );
      command.apply(doc);
      expect(_flatTiles(doc).sublist(0, 2), [7, 7]);
      expect(_flatTiles(doc)[5], 7);
      expect(
        _flatTiles(doc)[2],
        1,
        reason: 'the solid wall is a different id, so untouched',
      );

      command.revert(doc);
      expect(_snapshot(doc), before);
    });

    test('filling a region with the id it already has changes nothing', () {
      final doc = _legendLevel();
      FlattenTileMapCommand(_map(doc)).apply(doc);
      final before = _snapshot(doc);
      final command = FillRegionCommand(
        entity: _map(doc),
        col: 0,
        row: 0,
        tileId: 0,
      );
      command.apply(doc);
      command.revert(doc);
      expect(_snapshot(doc), before);
    });
  });

  group('MoveEntityCommand', () {
    test('moves an entity and reverts to its previous position', () {
      final doc = _legendLevel();
      final map = _map(doc);
      final before = _snapshot(doc);
      final command = MoveEntityCommand(entity: map, x: 40.0, y: 50.0);
      command.apply(doc);
      expect(map.components['position'], {'x': 40.0, 'y': 50.0});
      command.revert(doc);
      expect(_snapshot(doc), before);
    });

    test('removes a position it created when reverting', () {
      final doc = LevelDocument.fromJson({
        'entities': [
          {'components': <String, dynamic>{}},
        ],
      });
      final entity = doc.entities.single;
      final command = MoveEntityCommand(entity: entity, x: 1.0, y: 2.0);
      command.apply(doc);
      command.revert(doc);
      expect(entity.components.containsKey('position'), isFalse);
    });
  });
}
