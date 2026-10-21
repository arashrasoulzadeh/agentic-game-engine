import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

LevelEntity _entity(
  String? name,
  double x,
  double y, [
  Map<String, Map<String, dynamic>> extra = const {},
]) => LevelEntity(
  name: name,
  components: {
    'position': {'x': x, 'y': y},
    ...extra,
  },
);

LevelEntity _mapEntity({int cols = 5, int rows = 4}) => LevelEntity(
  name: 'map',
  components: {
    'position': {'x': 0.0, 'y': 0.0},
    'tileMap': {
      'cols': cols,
      'rows': rows,
      'tileWidth': 16.0,
      'tileHeight': 16.0,
      'tiles': List<int>.filled(cols * rows, 0),
    },
  },
);

List<int> _tiles(LevelEntity e) =>
    (e.components['tileMap']!['tiles'] as List).cast<int>();

void main() {
  group('TMX export', () {
    TileMap sample() => TileMap(
      cols: 4,
      rows: 3,
      tileWidth: 16,
      tileHeight: 16,
      tiles: [0, 1, 1, 2, 0, 3, 0, 4, 1, 1, 1, 0],
      solidTileIds: {1},
      oneWayTileIds: {2},
      slopeUpRightTileIds: {3},
      slopeUpLeftTileIds: {4},
    );

    test(
      'round trips through the importer: size, every tile, and the four collision sets',
      () {
        final original = sample();
        final back = tileMapFromTmx(tileMapToTmx(original));
        expect(
          (back.cols, back.rows, back.tileWidth, back.tileHeight),
          (4, 3, 16, 16),
        );
        expect(back.tiles, original.tiles);
        expect(back.solidTileIds, original.solidTileIds);
        expect(back.oneWayTileIds, original.oneWayTileIds);
        expect(back.slopeUpRightTileIds, original.slopeUpRightTileIds);
        expect(back.slopeUpLeftTileIds, original.slopeUpLeftTileIds);
      },
    );

    test(
      'writes what Tiled expects: firstgid 1, a tileset image, CSV data, whole-number sizes',
      () {
        final tmx = tileMapToTmx(
          sample(),
          tilesetName: 'dungeon',
          imageSource: 'art/dungeon.png',
        );
        expect(tmx, contains('firstgid="1"'));
        expect(tmx, contains('name="dungeon"'));
        expect(tmx, contains('source="art/dungeon.png"'));
        expect(tmx, contains('encoding="csv"'));
        expect(tmx, contains('tilewidth="16"'));
        expect(tmx, isNot(contains('16.0')));
        expect(tmx, contains('tilecount="4"'));
      },
    );

    test(
      'fractional tile sizes and a tile with several properties survive',
      () {
        final map = TileMap(
          cols: 2,
          rows: 1,
          tileWidth: 12.5,
          tileHeight: 8,
          tiles: [1, 0],
          solidTileIds: {1},
          oneWayTileIds: {1},
        );
        final back = tileMapFromTmx(tileMapToTmx(map));
        expect(back.tileWidth, 12.5);
        expect(back.solidTileIds, {1});
        expect(back.oneWayTileIds, {1}, reason: 'both properties on one tile');
      },
    );

    test('a map with no collision data still exports and re-imports', () {
      final map = TileMap(
        cols: 2,
        rows: 2,
        tileWidth: 8,
        tileHeight: 8,
        tiles: [0, 0, 0, 0],
      );
      final back = tileMapFromTmx(tileMapToTmx(map));
      expect(back.tiles, [0, 0, 0, 0]);
      expect(back.solidTileIds, isEmpty);
    });

    test('what TMX cannot hold is dropped on re-import, as documented', () {
      final map = TileMap(
        cols: 2,
        rows: 1,
        tileWidth: 16,
        tileHeight: 16,
        tiles: [1, 0],
        ladderTileIds: {1},
        frictionByTileId: {1: 0.2},
        atlasId: 'art',
      );
      final back = tileMapFromTmx(tileMapToTmx(map));
      expect(back.tiles, [1, 0]);
      expect(back.ladderTileIds, isEmpty);
      expect(back.atlasId, isNull);
    });

    test('a tileset image size can be given explicitly', () {
      final tmx = tileMapToTmx(
        sample(),
        imageWidth: 512,
        imageHeight: 128,
        columns: 16,
      );
      expect(tmx, contains('width="512"'));
      expect(tmx, contains('columns="16"'));
    });
  });

  group('Prefab', () {
    test(
      'fromEntities stores positions relative to the group\'s top-left and deep-copies',
      () {
        final source = [
          _entity('a', 100, 50, {
            'health': {'value': 3},
          }),
          _entity('b', 130, 80),
          LevelEntity(
            name: 'unpositioned',
            components: {
              'tag': {'x': 1},
            },
          ),
        ];
        final prefab = Prefab.fromEntities('room', source);
        expect(prefab.entities[0].components['position'], {'x': 0.0, 'y': 0.0});
        expect(prefab.entities[1].components['position'], {
          'x': 30.0,
          'y': 30.0,
        });
        expect(prefab.entities[2].components.containsKey('position'), isFalse);

        source[0].components['health']!['value'] = 99;
        expect(
          prefab.entities[0].components['health']!['value'],
          3,
          reason: 'later level edits don\'t change it',
        );
      },
    );

    test(
      'instantiate offsets positions and returns independent copies each time',
      () {
        final prefab = Prefab.fromEntities('p', [
          _entity(null, 0, 0),
          _entity(null, 10, 20),
        ]);
        final one = prefab.instantiate(100, 200);
        final two = prefab.instantiate(100, 200);
        expect(one[1].components['position'], {'x': 110.0, 'y': 220.0});
        one[0].components['position']!['x'] = -5.0;
        expect(two[0].components['position']!['x'], 100.0);
        expect(
          prefab.entities[0].components['position']!['x'],
          0.0,
          reason: 'the template is untouched',
        );
      },
    );

    test('names are made unique against the level and within the batch', () {
      final prefab = Prefab.fromEntities('p', [
        _entity('torch', 0, 0),
        _entity('torch', 5, 0),
        _entity('door', 9, 0),
      ]);
      final placed = prefab.instantiate(0, 0, taken: {'torch', 'door'});
      expect([for (final e in placed) e.name], ['torch2', 'torch3', 'door2']);
    });

    test('JSON round trip, and an empty prefab is fine', () {
      final prefab = Prefab.fromEntities('p', [_entity('a', 3, 4)]);
      final back = Prefab.fromJson(
        jsonDecode(jsonEncode(prefab.toJson())) as Map<String, dynamic>,
      );
      expect(back.name, 'p');
      expect(back.entities.single.name, 'a');
      expect(Prefab.fromJson({'name': 'e'}).entities, isEmpty);
      expect(Prefab.fromEntities('e', const []).instantiate(1, 2), isEmpty);
    });
  });

  group('InstantiatePrefabCommand (undo is one step)', () {
    test(
      'apply adds every entity, revert removes them all, redo puts back the same objects',
      () {
        final doc = LevelDocument(entities: [_entity('keep', 0, 0)]);
        final prefab = Prefab.fromEntities('room', [
          _entity('a', 0, 0),
          _entity('b', 10, 0),
          _entity('c', 20, 0),
        ]);
        final history = CommandHistory(doc);
        final command = InstantiatePrefabCommand(prefab, x: 50, y: 60);
        history.execute(command);
        expect(doc.entities, hasLength(4));
        expect(command.placed, hasLength(3));
        final placedBefore = command.placed;
        expect(doc.entities.last.components['position'], {
          'x': 70.0,
          'y': 60.0,
        });

        history.undo();
        expect(
          doc.entities,
          hasLength(1),
          reason: 'one undo removes the whole group',
        );
        expect(doc.entities.single.name, 'keep');

        history.redo();
        expect(doc.entities, hasLength(4));
        expect(
          identical(command.placed.first, placedBefore.first),
          isTrue,
          reason: 'the same entities come back',
        );
        expect(history.canUndo, isTrue);
      },
    );

    test(
      'placing twice gives two independent groups with unique names, each undone separately',
      () {
        final doc = LevelDocument();
        final prefab = Prefab.fromEntities('torch', [_entity('torch', 0, 0)]);
        final history = CommandHistory(doc);
        history.execute(InstantiatePrefabCommand(prefab, x: 0, y: 0));
        history.execute(InstantiatePrefabCommand(prefab, x: 40, y: 0));
        expect([for (final e in doc.entities) e.name], ['torch', 'torch2']);
        history.undo();
        expect([for (final e in doc.entities) e.name], ['torch']);
        history.undo();
        expect(doc.entities, isEmpty);
      },
    );

    test(
      'editing a placed entity and then undoing both restores the original state',
      () {
        final doc = LevelDocument();
        final prefab = Prefab.fromEntities('p', [
          _entity('a', 0, 0, {
            'health': {'value': 1},
          }),
        ]);
        final history = CommandHistory(doc);
        final place = InstantiatePrefabCommand(prefab, x: 0, y: 0);
        history.execute(place);
        history.execute(
          SetComponentFieldCommand(
            entity: place.placed.single,
            component: 'health',
            field: 'value',
            value: 9,
          ),
        );
        history.undo();
        expect(place.placed.single.components['health']!['value'], 1);
        history.undo();
        expect(doc.entities, isEmpty);
      },
    );

    test('the label names the prefab', () {
      final c = InstantiatePrefabCommand(
        Prefab(name: 'castle', entities: const []),
        x: 0,
        y: 0,
      );
      expect(c.label, 'Place castle');
      expect(c.placed, isEmpty);
    });
  });

  group('Brush', () {
    test('a tile brush stamps its pattern as one undoable step', () {
      final doc = LevelDocument(entities: [_mapEntity()]);
      final map = doc.entities.single;
      final brush = TileBrush(
        name: 'ledge',
        pattern: [
          [1, 1, 1],
          [0, 2, 0],
        ],
      );
      expect((brush.width, brush.height), (3, 2));
      final history = CommandHistory(doc);
      history.execute(brush.stampAt(map, 1, 1)!);
      final tiles = _tiles(map);
      expect(tiles[1 * 5 + 1], 1);
      expect(tiles[1 * 5 + 3], 1);
      expect(tiles[2 * 5 + 2], 2);
      history.undo();
      expect(
        _tiles(map).every((t) => t == 0),
        isTrue,
        reason: 'every stamped cell is restored by a single undo',
      );
    });

    test('skip leaves a cell alone, and 0 erases', () {
      final doc = LevelDocument(entities: [_mapEntity()]);
      final map = doc.entities.single;
      (map.components['tileMap']!['tiles'] as List)[0] = 7;
      (map.components['tileMap']!['tiles'] as List)[1] = 7;
      final brush = TileBrush(
        name: 'hole',
        pattern: [
          [TileBrush.skip, 0],
        ],
      );
      CommandHistory(doc).execute(brush.stampAt(map, 0, 0)!);
      expect(_tiles(map).take(2), [
        7,
        0,
      ], reason: 'the skip kept 7; the 0 erased the other');
    });

    test(
      'a stamp near the edge is clipped; fully outside is a no-op (null)',
      () {
        final doc = LevelDocument(entities: [_mapEntity(cols: 4, rows: 3)]);
        final map = doc.entities.single;
        final brush = TileBrush(
          name: 'b',
          pattern: [
            [5, 5],
            [5, 5],
          ],
        );
        CommandHistory(doc).execute(brush.stampAt(map, 3, 2)!);
        expect(
          _tiles(map).where((t) => t == 5),
          hasLength(1),
          reason: 'only the corner cell is inside',
        );
        expect(brush.stampAt(map, 50, 50), isNull);
        expect(brush.stampAt(map, -9, -9), isNull);
        expect(brush.stampAt(LevelEntity(name: 'nomap'), 0, 0), isNull);
      },
    );

    test('invalid patterns are rejected', () {
      expect(
        () => TileBrush(name: 'x', pattern: const []),
        throwsArgumentError,
      );
      expect(
        () => TileBrush(name: 'x', pattern: const [[]]),
        throwsArgumentError,
      );
      expect(
        () => TileBrush(
          name: 'x',
          pattern: const [
            [1, 1],
            [1],
          ],
        ),
        throwsArgumentError,
      );
    });

    test('a prefab brush places its prefab', () {
      final doc = LevelDocument();
      final brush = const PrefabBrush(
        name: 'torch',
        prefabPath: 'prefabs/torch.json',
      );
      final prefab = Prefab.fromEntities('torch', [_entity('t', 0, 0)]);
      CommandHistory(doc).execute(brush.placeAt(prefab, 32, 48));
      expect(doc.entities.single.components['position'], {
        'x': 32.0,
        'y': 48.0,
      });
    });

    test(
      'the library replaces by name, removes, and round-trips both brush types',
      () {
        final lib = BrushLibrary()
          ..add(
            TileBrush(
              name: 'a',
              pattern: [
                [1],
              ],
            ),
          )
          ..add(const PrefabBrush(name: 'b', prefabPath: 'prefabs/b.json'))
          ..add(
            TileBrush(
              name: 'a',
              pattern: [
                [2, 2],
              ],
            ),
          );
        expect(lib.brushes, hasLength(2));
        expect(
          (lib.named('a') as TileBrush).width,
          2,
          reason: 'saving again replaced it',
        );
        expect(lib.named('zzz'), isNull);

        final back = BrushLibrary.fromJson(
          jsonDecode(jsonEncode(lib.toJson())) as Map<String, dynamic>,
        );
        expect(back.brushes.map((b) => b.name), ['a', 'b']);
        expect(back.named('b'), isA<PrefabBrush>());

        expect(lib.remove('a'), isTrue);
        expect(lib.remove('a'), isFalse);
      },
    );

    test('a bad entry is skipped, not fatal', () {
      final lib = BrushLibrary.fromJson({
        'brushes': [
          {
            'type': 'tiles',
            'name': 'ok',
            'pattern': [
              [1],
            ],
          },
          {'type': 'banana', 'name': 'bad'},
          {
            'type': 'tiles',
            'name': 'ragged',
            'pattern': [
              [1, 2],
              [3],
            ],
          },
          'not even a map',
        ],
      });
      expect(lib.brushes.map((b) => b.name), ['ok']);
      expect(BrushLibrary.fromJson({}).brushes, isEmpty);
    });
  });
}
