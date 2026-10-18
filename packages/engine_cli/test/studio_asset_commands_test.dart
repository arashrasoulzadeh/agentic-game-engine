import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

import 'support/run_studio.dart';
import 'support/run_studio_capture.dart';

Map<String, dynamic> _level() => {
  'entities': [
    {
      'name': 'map',
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'tileMap': {
          'cols': 3,
          'rows': 2,
          'tileWidth': 16.0,
          'tileHeight': 16.0,
          'tiles': [1, 1, 2, 0, 0, 0],
          'solidTileIds': [1],
          'oneWayTileIds': [2],
        },
      },
    },
    {
      'name': 'torch',
      'components': {
        'position': {'x': 100.0, 'y': 50.0},
      },
    },
    {
      'name': 'flame',
      'components': {
        'position': {'x': 110.0, 'y': 40.0},
      },
    },
  ],
};

void main() {
  late Directory dir;
  late String level;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('studio_assets');
    level = '${dir.path}/level.json';
    File(level).writeAsStringSync(jsonEncode(_level()));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('export-tmx', () {
    test('writes a .tmx the importer reads back to the same tiles', () async {
      final out = '${dir.path}/out.tmx';
      expect(await runStudio(['export-tmx', level, '--out', out]), 0);
      final back = tileMapFromTmx(File(out).readAsStringSync());
      expect(back.tiles, [1, 1, 2, 0, 0, 0]);
      expect(back.solidTileIds, {1});
      expect(back.oneWayTileIds, {2});
    });

    test(
      'the default output sits next to the level with a .tmx extension',
      () async {
        File(
          '${dir.path}/castle.level.json',
        ).writeAsStringSync(jsonEncode(_level()));
        expect(
          await runStudio(['export-tmx', '${dir.path}/castle.level.json']),
          0,
        );
        expect(File('${dir.path}/castle.tmx').existsSync(), isTrue);
      },
    );

    test('--image and --tileset are recorded', () async {
      final out = '${dir.path}/o.tmx';
      await runStudio([
        'export-tmx',
        level,
        '--out',
        out,
        '--image',
        'art/sheet.png',
        '--tileset',
        'dungeon',
      ]);
      final xml = File(out).readAsStringSync();
      expect(xml, contains('art/sheet.png'));
      expect(xml, contains('name="dungeon"'));
    });

    test(
      'a level with no tile map, an unknown entity, and a missing file are errors',
      () async {
        File(
          '${dir.path}/empty.json',
        ).writeAsStringSync(jsonEncode({'entities': []}));
        expect(await runStudio(['export-tmx', '${dir.path}/empty.json']), 1);
        expect(await runStudio(['export-tmx', level, '--entity', 'nope']), 1);
        expect(await runStudio(['export-tmx', '${dir.path}/missing.json']), 1);
      },
    );

    test('says when the level uses things Tiled cannot hold', () async {
      final json = _level();
      ((json['entities'] as List).first['components']['tileMap']
          as Map)['ladderTileIds'] = [
        1,
      ];
      File(level).writeAsStringSync(jsonEncode(json));
      final result = await runStudioCapture([
        'studio',
        'export-tmx',
        level,
        '--out',
        '${dir.path}/l.tmx',
      ]);
      expect(result.stdout, contains('ladders'));
    });
  });

  group('save-prefab and place-prefab', () {
    test(
      'save writes prefabs/<name>.json relative to the group, place puts it back at a new spot',
      () async {
        expect(
          await runStudio([
            'save-prefab',
            level,
            '--name',
            'torch',
            '--entities',
            'torch,flame',
            '--project',
            dir.path,
          ]),
          0,
        );
        final saved =
            jsonDecode(
                  File('${dir.path}/prefabs/torch.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        final prefab = Prefab.fromJson(saved);
        expect(prefab.entities.map((e) => e.name), ['torch', 'flame']);
        expect(prefab.entities[0].components['position'], {
          'x': 0.0,
          'y': 10.0,
        });
        expect(prefab.entities[1].components['position'], {
          'x': 10.0,
          'y': 0.0,
        });

        expect(
          await runStudio([
            'place-prefab',
            level,
            '--prefab',
            'torch',
            '--x',
            '200',
            '--y',
            '300',
            '--project',
            dir.path,
          ]),
          0,
        );
        final doc = LevelDocument.fromJson(
          jsonDecode(File(level).readAsStringSync()) as Map<String, dynamic>,
        );
        expect(doc.entities, hasLength(5));
        expect(doc.entities[3].name, 'torch2', reason: 'names stay unique');
        expect(doc.entities[3].components['position'], {
          'x': 200.0,
          'y': 310.0,
        });
      },
    );

    test(
      'bad names, unknown entities and empty selections are rejected without writing',
      () async {
        expect(
          await runStudio([
            'save-prefab',
            level,
            '--name',
            'bad name!',
            '--entities',
            'torch',
            '--project',
            dir.path,
          ]),
          1,
        );
        expect(
          await runStudio([
            'save-prefab',
            level,
            '--name',
            'x',
            '--entities',
            'ghost',
            '--project',
            dir.path,
          ]),
          1,
        );
        expect(
          await runStudio([
            'save-prefab',
            level,
            '--name',
            'x',
            '--entities',
            ' , ',
            '--project',
            dir.path,
          ]),
          1,
        );
        expect(Directory('${dir.path}/prefabs').existsSync(), isFalse);
      },
    );

    test(
      'placing a missing or corrupt prefab, or with a bad coordinate, leaves the level untouched',
      () async {
        final before = File(level).readAsStringSync();
        expect(
          await runStudio([
            'place-prefab',
            level,
            '--prefab',
            'nope',
            '--x',
            '1',
            '--y',
            '1',
            '--project',
            dir.path,
          ]),
          1,
        );
        Directory('${dir.path}/prefabs').createSync();
        File('${dir.path}/prefabs/broken.json').writeAsStringSync('{ nope');
        expect(
          await runStudio([
            'place-prefab',
            level,
            '--prefab',
            'broken',
            '--x',
            '1',
            '--y',
            '1',
            '--project',
            dir.path,
          ]),
          1,
        );
        File('${dir.path}/prefabs/ok.json').writeAsStringSync(
          jsonEncode(Prefab(name: 'ok', entities: []).toJson()),
        );
        expect(
          await runStudio([
            'place-prefab',
            level,
            '--prefab',
            'ok',
            '--x',
            'abc',
            '--y',
            '1',
            '--project',
            dir.path,
          ]),
          1,
        );
        expect(File(level).readAsStringSync(), before);
      },
    );
  });
}
