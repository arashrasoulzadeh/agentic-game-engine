import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/assets/asset_index.dart';
import 'package:engine_studio/src/assets/asset_references.dart';
import 'package:engine_studio/src/assets/project_stores.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void _write(Directory root, String path, String contents) {
  File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

String _manifest(List<String> names) => jsonEncode({
  'regions': {
    for (final n in names) n: {'x': 0, 'y': 0, 'w': 8, 'h': 8},
  },
});

LevelDocument _doc(List<Map<String, dynamic>> entities) =>
    LevelDocument.fromJson({'entities': entities});

Map<String, dynamic> _spriteEntity(String name, String atlas, String region) =>
    {
      'name': name,
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'sprite': {'atlasId': atlas, 'region': region},
      },
    };

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('assets_logic'));
  tearDown(() => root.deleteSync(recursive: true));

  group('AssetIndex.scan', () {
    test(
      'an empty project has nothing, and no declared atlases to check against',
      () {
        final index = AssetIndex.scan(root.path);
        expect(index.atlases, isEmpty);
        expect(index.images, isEmpty);
        expect(index.declaredRegions, isNull);
      },
    );

    test('a declared atlas gets its catalog id and its sprite names', () {
      _write(
        root,
        'assets/studio_atlases.json',
        jsonEncode({
          'atlases': {
            'hero': {
              'image': 'assets/hero.png',
              'manifest': 'assets/hero.json',
            },
          },
        }),
      );
      _write(root, 'assets/hero.png', 'png');
      _write(root, 'assets/hero.json', _manifest(['walk', 'idle']));
      final index = AssetIndex.scan(root.path);
      final hero = index.atlasById('hero')!;
      expect(hero.declared, isTrue);
      expect(hero.regions, ['idle', 'walk'], reason: 'sorted');
      expect(hero.image, 'assets/hero.png');
      expect(index.declaredRegions, {
        'hero': {'idle', 'walk'},
      });
      expect(
        index.images,
        isEmpty,
        reason: 'the atlas image is not listed twice',
      );
    });

    test(
      'a freshly packed sheet (png + manifest side by side) shows up undeclared',
      () {
        _write(root, 'assets/packed/atlas.png', 'png');
        _write(root, 'assets/packed/atlas.json', _manifest(['coin']));
        final index = AssetIndex.scan(root.path);
        final atlas = index.atlases.single;
        expect(atlas.id, 'atlas');
        expect(atlas.declared, isFalse);
        expect(atlas.regions, ['coin']);
        expect(
          index.declaredRegions,
          isNull,
          reason: 'undeclared atlases are not valid references',
        );
        expect(index.images, isEmpty);
        expect(
          index.data,
          isEmpty,
          reason: 'the manifest is part of the atlas',
        );
      },
    );

    test('everything else is sorted into images, audio, data and prefabs', () {
      _write(root, 'assets/logo.png', 'x');
      _write(root, 'assets/sfx/jump.WAV', 'x');
      _write(root, 'assets/music.ogg', 'x');
      _write(root, 'assets/config/balance.json', '{}');
      _write(root, 'assets/levels/one.level.json', '{}');
      _write(root, 'assets/studio_brushes.json', '{}');
      _write(root, 'prefabs/torch.json', '{}');
      _write(root, 'assets/readme.txt', 'x');
      final index = AssetIndex.scan(root.path);
      expect(index.images, ['assets/logo.png']);
      expect(index.audio, ['assets/music.ogg', 'assets/sfx/jump.WAV']);
      expect(index.data, [
        'assets/config/balance.json',
      ], reason: 'levels and studio files are not data');
      expect(index.prefabs, ['prefabs/torch.json']);
    });

    test('a broken or region-less manifest is skipped, not fatal', () {
      _write(root, 'assets/a.png', 'x');
      _write(root, 'assets/a.json', '{ nope');
      _write(root, 'assets/b.png', 'x');
      _write(root, 'assets/b.json', '{"something": 1}');
      _write(root, 'assets/c.json', _manifest(['x'])); // no sibling image
      final index = AssetIndex.scan(root.path);
      expect(index.atlases, isEmpty);
      expect(index.images, containsAll(['assets/a.png', 'assets/b.png']));
    });

    test('a catalog entry whose manifest is missing is left out', () {
      _write(
        root,
        'assets/studio_atlases.json',
        jsonEncode({
          'atlases': {
            'ghost': {'image': 'assets/g.png', 'manifest': 'assets/g.json'},
          },
        }),
      );
      expect(AssetIndex.scan(root.path).atlases, isEmpty);
    });
  });

  group('checkAssetReferences', () {
    final known = {
      'hero': {'idle', 'walk'},
    };

    test('valid references and a project with no atlases produce nothing', () {
      expect(
        checkAssetReferences(_doc([_spriteEntity('p', 'hero', 'idle')]), known),
        isEmpty,
      );
      expect(
        checkAssetReferences(
          _doc([_spriteEntity('p', 'anything', 'goes')]),
          null,
        ),
        isEmpty,
      );
    });

    test(
      'an undeclared atlas and a missing sprite are errors that point at the entity',
      () {
        final doc = _doc([
          _spriteEntity('ok', 'hero', 'idle'),
          _spriteEntity('lost', 'ghost', 'x'),
          _spriteEntity('typo', 'hero', 'runn'),
        ]);
        final issues = checkAssetReferences(doc, known);
        expect(issues, hasLength(2));
        expect(issues[0].entityIndex, 1);
        expect(issues[0].message, contains('"ghost" is not declared'));
        expect(issues[1].entityIndex, 2);
        expect(issues[1].entityName, 'typo');
        expect(issues[1].component, 'sprite');
        expect(issues[1].message, contains('no sprite named "runn"'));
        expect(issues.every((i) => i.severity == IssueSeverity.error), isTrue);
      },
    );

    test('tile maps check their atlas and each per-tile region', () {
      final doc = _doc([
        {
          'name': 'map',
          'components': {
            'position': {'x': 0.0, 'y': 0.0},
            'tileMap': {
              'cols': 1,
              'rows': 1,
              'tileWidth': 16.0,
              'tileHeight': 16.0,
              'tiles': [1],
              'atlasId': 'hero',
              'regionByTileId': {'1': 'idle', '2': 'missing'},
            },
          },
        },
      ]);
      final issues = checkAssetReferences(doc, known);
      expect(issues.single.message, contains('"missing"'));
      expect(issues.single.component, 'tileMap');
    });

    test(
      'a sprite or tile map with no atlas id is not this check\'s business',
      () {
        final doc = _doc([
          {
            'components': {
              'position': {'x': 0.0, 'y': 0.0},
              'sprite': {'region': 'x'},
            },
          },
        ]);
        expect(checkAssetReferences(doc, known), isEmpty);
      },
    );
  });

  group('stores', () {
    test(
      'BrushStore round trips and treats a missing or corrupt file as empty',
      () {
        final store = BrushStore(root.path);
        expect(store.load().brushes, isEmpty);
        store.save(
          BrushLibrary()
            ..add(
              TileBrush(
                name: 'ledge',
                pattern: [
                  [1, 1],
                ],
              ),
            )
            ..add(
              const PrefabBrush(
                name: 'torch',
                prefabPath: 'prefabs/torch.json',
              ),
            ),
        );
        expect(
          File('${root.path}/assets/studio_brushes.json').existsSync(),
          isTrue,
        );
        expect(store.load().brushes.map((b) => b.name), ['ledge', 'torch']);

        File(
          '${root.path}/assets/studio_brushes.json',
        ).writeAsStringSync('garbage');
        expect(store.load().brushes, isEmpty);
      },
    );

    test(
      'PrefabStore saves, lists and loads; rejects unusable names; tolerates corruption',
      () {
        final store = PrefabStore(root.path);
        expect(store.list(), isEmpty);
        final prefab = Prefab.fromEntities('torch', [
          LevelEntity(
            name: 't',
            components: {
              'position': {'x': 5.0, 'y': 5.0},
            },
          ),
        ]);
        expect(store.save(prefab), 'prefabs/torch.json');
        expect(store.list(), ['prefabs/torch.json']);
        expect(store.load('prefabs/torch.json')!.entities.single.name, 't');
        expect(store.load('prefabs/missing.json'), isNull);

        File('${root.path}/prefabs/bad.json').writeAsStringSync('{ no');
        expect(store.load('prefabs/bad.json'), isNull);

        expect(PrefabStore.isValidName('ok-name_1'), isTrue);
        expect(PrefabStore.isValidName('has space'), isFalse);
        expect(PrefabStore.isValidName('../escape'), isFalse);
        expect(PrefabStore.isValidName(''), isFalse);
        expect(
          () => store.save(Prefab(name: '../escape', entities: const [])),
          throwsArgumentError,
        );
      },
    );
  });

  group('LevelEditor: stamp tool, prefabs, asset issues', () {
    LevelEditor editorWithMap({int cols = 6, int rows = 4}) => LevelEditor(
      _doc([
        {
          'name': 'map',
          'components': {
            'position': {'x': 0.0, 'y': 0.0},
            'tileMap': {
              'cols': cols,
              'rows': rows,
              'tileWidth': 16.0,
              'tileHeight': 16.0,
              'tiles': List<int>.filled(cols * rows, 0),
            },
          },
        },
      ]),
    );

    List<int> tiles(LevelEditor e) =>
        (e.document.entities.first.components['tileMap']!['tiles'] as List)
            .cast<int>();

    test('with no brush the stamp tool does nothing', () {
      final e = editorWithMap()..tool = EditorTool.stamp;
      e.tap(const Offset(20, 20));
      expect(tiles(e).every((t) => t == 0), isTrue);
      expect(e.history.canUndo, isFalse);
    });

    test(
      'a tile brush stamps from the tapped cell, and one undo reverts all of it',
      () {
        final e = editorWithMap()
          ..tool = EditorTool.stamp
          ..activeBrush = TileBrush(
            name: 'b',
            pattern: [
              [1, 1],
              [2, 2],
            ],
          );
        e.tap(const Offset(20, 20)); // cell (1, 1)
        expect(tiles(e)[1 * 6 + 1], 1);
        expect(tiles(e)[1 * 6 + 2], 1);
        expect(tiles(e)[2 * 6 + 1], 2);
        expect(tiles(e).where((t) => t != 0), hasLength(4));
        e.undo();
        expect(tiles(e).every((t) => t == 0), isTrue);
      },
    );

    test('a tap outside the map stamps nothing', () {
      final e = editorWithMap()
        ..tool = EditorTool.stamp
        ..activeBrush = TileBrush(
          name: 'b',
          pattern: [
            [3],
          ],
        );
      e.tap(const Offset(900, 900));
      expect(e.history.canUndo, isFalse);
    });

    test(
      'a prefab brush places the prefab at the tapped point (snapped), selects it, undoes in one step',
      () {
        final prefab = Prefab.fromEntities('torch', [
          LevelEntity(
            name: 'torch',
            components: {
              'position': {'x': 0.0, 'y': 0.0},
            },
          ),
          LevelEntity(
            name: 'flame',
            components: {
              'position': {'x': 8.0, 'y': -8.0},
            },
          ),
        ]);
        final e = LevelEditor(_doc([]))
          ..tool = EditorTool.stamp
          ..snapToGrid = true
          ..gridSize = 16
          ..activeBrush = const PrefabBrush(
            name: 'torch',
            prefabPath: 'prefabs/torch.json',
          )
          ..prefabLoader = (path) =>
              path == 'prefabs/torch.json' ? prefab : null;
        e.tap(const Offset(37, 21));
        expect(e.document.entities, hasLength(2));
        // The prefab's top-left is the flame (y = -8), so the torch is 8 below that corner.
        expect(e.document.entities.first.components['position'], {
          'x': 32.0,
          'y': 24.0,
        });
        expect(e.document.entities.last.components['position'], {
          'x': 40.0,
          'y': 16.0,
        });
        expect(e.selected, same(e.document.entities.first));
        e.undo();
        expect(e.document.entities, isEmpty);
        expect(e.selected, isNull, reason: 'the selection followed the undo');
      },
    );

    test('a prefab brush whose file is missing places nothing', () {
      final e = LevelEditor(_doc([]))
        ..tool = EditorTool.stamp
        ..activeBrush = const PrefabBrush(
          name: 'gone',
          prefabPath: 'prefabs/gone.json',
        )
        ..prefabLoader = (_) => null;
      e.tap(const Offset(1, 1));
      expect(e.document.entities, isEmpty);
      final noLoader = LevelEditor(_doc([]))
        ..tool = EditorTool.stamp
        ..activeBrush = const PrefabBrush(name: 'x', prefabPath: 'p');
      noLoader.tap(const Offset(1, 1));
      expect(noLoader.document.entities, isEmpty);
    });

    test(
      'prefabFromSelection captures the selected entity relative to itself',
      () {
        final e = LevelEditor(_doc([_spriteEntity('hero', 'a', 'b')]));
        expect(e.prefabFromSelection('x'), isNull);
        e.selectIndex(0);
        final prefab = e.prefabFromSelection('hero')!;
        expect(prefab.name, 'hero');
        expect(prefab.entities.single.components['position'], {
          'x': 0.0,
          'y': 0.0,
        });
      },
    );

    test(
      'missing sprites show up in issues only once atlas regions are known',
      () {
        final e = LevelEditor(_doc([_spriteEntity('p', 'hero', 'runn')]));
        expect(e.issues.where((i) => i.message.contains('runn')), isEmpty);
        e.atlasRegions = {
          'hero': {'idle'},
        };
        final bad = e.issues.where((i) => i.message.contains('runn')).single;
        expect(bad.entityIndex, 0);
        e.selectIndex(bad.entityIndex);
        expect(
          e.selected!.name,
          'p',
          reason: 'clicking the problem selects the entity',
        );
        e.atlasRegions = {
          'hero': {'idle', 'runn'},
        };
        expect(e.issues.where((i) => i.message.contains('runn')), isEmpty);
      },
    );
  });
}
