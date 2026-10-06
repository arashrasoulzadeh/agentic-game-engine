import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/run_studio.dart';

/// Shorthand for the import-tmx command in these tests.
Future<int> _run(List<String> args) => runStudio(args);

const _tmx = '''
<map version="1.10" orientation="orthogonal" width="3" height="2" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="tiles" tilewidth="16" tileheight="16" tilecount="3" columns="3">
  <image source="tiles.png" width="48" height="16"/>
  <tile id="0"><properties><property name="solid" type="bool" value="true"/></properties></tile>
 </tileset>
 <layer id="1" name="Tile Layer 1" width="3" height="2">
  <data encoding="csv">
1,1,3,
0,0,0
</data>
 </layer>
</map>
''';

const _externalTileset = '''
<map version="1.10" orientation="orthogonal" width="1" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" source="tiles.tsx"/>
 <layer id="1" name="L" width="1" height="1"><data encoding="csv">1</data></layer>
</map>
''';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('studio_import'));
  tearDown(() => dir.deleteSync(recursive: true));

  File _write(String name, String contents) =>
      File('${dir.path}/$name')..writeAsStringSync(contents);

  test('imports a Tiled map into a valid level file in the project', () async {
    final source = _write('level1.tmx', _tmx);
    final code = await _run(['import-tmx', source.path, '--project', dir.path]);
    expect(code, 0);

    final out = File('${dir.path}/assets/levels/level1.level.json');
    expect(out.existsSync(), isTrue);
    final json = jsonDecode(out.readAsStringSync()) as Map<String, dynamic>;
    final tileMap =
        (json['entities'] as List).single['components']['tileMap'] as Map;
    expect(tileMap['cols'], 3);
    expect(tileMap['rows'], 2);
    expect(tileMap['tiles'], [1, 1, 3, 0, 0, 0]);
    expect(tileMap['solidTileIds'], isA<List>());
  });

  test('writes to --out when given, instead of the default path', () async {
    final source = _write('level1.tmx', _tmx);
    final target = '${dir.path}/custom.json';
    expect(await _run(['import-tmx', source.path, '--out', target]), 0);
    expect(File(target).existsSync(), isTrue);
  });

  test('refuses an external tileset and writes nothing', () async {
    final source = _write('external.tmx', _externalTileset);
    expect(await _run(['import-tmx', source.path, '--project', dir.path]), 1);
    expect(Directory('${dir.path}/assets').existsSync(), isFalse);
  });

  test('exits 1 for a missing .tmx file', () async {
    expect(await _run(['import-tmx', '${dir.path}/nope.tmx']), 1);
  });
}
