import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

const lv = 'assets/levels/level1.json';

void main() {
  test('export then import round-trips the tiles and solid set', () async {
    final s = await Scratch.create();
    final out = await s.map('level.export_tmx', {'path': lv});
    expect(out['path'], 'assets/levels/level1.tmx');
    expect(out['cols'], 4);
    expect(out['lost'], isEmpty);
    expect(s.read('assets/levels/level1.tmx'), contains('<map'));

    final imp = await s.map('level.import_tmx', {
      'tmx': 'assets/levels/level1.tmx',
      'output': 'assets/levels/copy.json',
      'entity': 'floor',
    });
    expect(imp['path'], 'assets/levels/copy.json');
    final entity =
        (jsonDecode(s.read('assets/levels/copy.json'))['entities'] as List)
                .single
            as Map;
    expect(entity['name'], 'floor');
    final tileMap = (entity['components'] as Map)['tileMap'] as Map;
    expect(tileMap['tiles'], [0, 0, 0, 0, 1, 1, 1, 1]);
    expect(tileMap['solidTileIds'], [1]);
  });

  test(
    'export names what Tiled cannot hold; missing tileMap or entity is not_found',
    () async {
      final s = await Scratch.create();
      expect(
        await s.failure('level.export_tmx', {
          'path': 'assets/levels/empty.json',
        }),
        ErrorCode.notFound,
      );
      expect(
        await s.failure('level.export_tmx', {'path': lv, 'entity': 'player'}),
        ErrorCode.notFound,
      );
    },
  );

  test('import_tmx needs layer for a multi-layer map and honors it', () async {
    final s = await Scratch.create();
    s.write('assets/levels/two.tmx', '''
<map width="2" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="2" columns="2">
  <image source="a.png" width="32" height="16"/>
 </tileset>
 <layer id="1" name="sky" width="2" height="1"><data encoding="csv">2,2</data></layer>
 <layer id="2" name="ground" width="2" height="1"><data encoding="csv">1,0</data></layer>
</map>
''');
    expect(
      await s.failure('level.import_tmx', {'tmx': 'assets/levels/two.tmx'}),
      ErrorCode.validationFailed,
    );
    final imp = await s.map('level.import_tmx', {
      'tmx': 'assets/levels/two.tmx',
      'layer': 'ground',
    });
    final entity =
        (jsonDecode(s.read(imp['path']! as String))['entities'] as List).single
            as Map;
    final tileMap = (entity['components'] as Map)['tileMap'] as Map;
    expect(tileMap['tiles'], [1, 0]);
  });

  test('import_tmx reads an external .tsx next to the map', () async {
    final s = await Scratch.create();
    s.write('assets/levels/tiles/ground.tsx', '''
<tileset name="ground" tilewidth="16" tileheight="16" tilecount="2" columns="2">
 <image source="g.png" width="32" height="16"/>
 <tile id="1"><properties><property name="solid" type="bool" value="true"/></properties></tile>
</tileset>
''');
    s.write('assets/levels/ext.tmx', '''
<map width="2" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" source="tiles/ground.tsx"/>
 <layer id="1" width="2" height="1"><data encoding="csv">2,1</data></layer>
</map>
''');
    final imp = await s.map('level.import_tmx', {
      'tmx': 'assets/levels/ext.tmx',
    });
    final entity =
        (jsonDecode(s.read(imp['path']! as String))['entities'] as List).single
            as Map;
    final tileMap = (entity['components'] as Map)['tileMap'] as Map;
    expect(tileMap['solidTileIds'], [2]);
  });

  test('import refuses an existing output and unsupported maps', () async {
    final s = await Scratch.create();
    await s.data('level.export_tmx', {'path': lv});
    expect(
      await s.failure('level.import_tmx', {
        'tmx': 'assets/levels/level1.tmx',
        'output': lv,
      }),
      ErrorCode.conflict,
    );
    s.write('assets/levels/bad.tmx', '<notamap/>');
    expect(
      await s.failure('level.import_tmx', {'tmx': 'assets/levels/bad.tmx'}),
      ErrorCode.validationFailed,
    );
    expect(
      await s.failure('level.import_tmx', {'tmx': 'assets/levels/none.tmx'}),
      ErrorCode.notFound,
    );
  });

  test(
    'no operation can write into .studio (token, undo journal) or .git',
    () async {
      final s = await Scratch.create();
      s.write('.studio/api-token', 'secret');
      for (final out in [
        '.studio/api-token',
        './.studio/undo/x.tmx',
        '.git/config',
        'assets/../.studio/y',
      ]) {
        final r = await s.call('level.export_tmx', {'path': lv, 'output': out});
        expect(
          r.error?.code,
          anyOf(ErrorCode.forbidden, ErrorCode.invalidParams),
          reason: out,
        );
      }
      expect(s.read('.studio/api-token'), 'secret');
      expect(s.exists('.git/config'), isFalse);
      expect(
        (await s.call('level.export_tmx', {
          'path': lv,
          'output': 'assets/ok.tmx',
        })).ok,
        isTrue,
      );
    },
  );
}
