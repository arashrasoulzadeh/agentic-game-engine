import 'dart:io';

import 'package:test/test.dart';

import 'support/run_studio_capture.dart';

File _level(String json) {
  final dir = Directory.systemTemp.createTempSync('studio_golden');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/level.json')..writeAsStringSync(json);
  return file;
}

Directory _project(String levelJson, {String name = 'level.json'}) {
  final dir = Directory.systemTemp.createTempSync('studio_golden_proj');
  addTearDown(() => dir.deleteSync(recursive: true));
  final levels = Directory('${dir.path}/assets/levels')
    ..createSync(recursive: true);
  File('${levels.path}/$name').writeAsStringSync(levelJson);
  return dir;
}

const _empty = '{"entities": []}';

const _withPlayer = '''
{
  "entities": [
    {"name": "player", "components": {"position": {"x": 1, "y": 2}}}
  ]
}
''';

const _withTileMap = '''
{
  "entities": [
    {"name": "map", "components": {
      "position": {"x": 0, "y": 0},
      "tileMap": {
        "tileWidth": 10, "tileHeight": 10,
        "legend": {".": 0, "#": 1},
        "rows": ["..", ".."]
      }
    }}
  ]
}
''';

void main() {
  group('validate', () {
    test('valid level: prints OK with entity count and exits 0', () async {
      final project = _project(_withPlayer);
      final result = await runStudioCapture([
        'studio',
        'validate',
        project.path,
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('OK (1 entities)'));
      expect(result.stdout, contains('1 level(s): 0 error(s), 0 warning(s).'));
    });

    test('invalid level: prints error details and exits 1', () async {
      final project = _project(
        '{"entities": [{"components": {"position": {"x": "left"}}}]}',
      );
      final result = await runStudioCapture([
        'studio',
        'validate',
        project.path,
      ]);
      expect(result.exitCode, 1);
      expect(result.stdout, contains('error:'));
      expect(result.stdout, contains('x must be a number'));
    });

    test('--strict: warning becomes error and exits 1', () async {
      const walled = '''
{
  "entities": [
    {"name": "map", "components": {"position": {"x": 0, "y": 0}, "tileMap": {"tileWidth": 10, "tileHeight": 10, "legend": {".": 0, "#": 1}, "rows": ["..#..", "..#..", "#####"]}}},
    {"name": "player", "components": {"position": {"x": 15, "y": 15}}},
    {"name": "exit", "components": {"position": {"x": 45, "y": 15}, "roomExit": {"targetSceneId": "next", "spawnPoint": "entrance"}}}
  ]
}
''';
      final project = _project(walled);
      final result = await runStudioCapture([
        'studio',
        'validate',
        project.path,
        '--strict',
      ]);
      expect(result.exitCode, 1);
      expect(result.stdout, contains('warning:'));
      expect(result.stdout, contains('not reachable'));
    });
  });

  group('add-entity', () {
    test('prints added entity message', () async {
      final file = _level(_empty);
      final result = await runStudioCapture([
        'studio',
        'add-entity',
        file.path,
        '--name',
        'coin',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, 'Added entity coin to ${file.path}.\n');
    });

    test('prints message without name when none given', () async {
      final file = _level(_empty);
      final result = await runStudioCapture([
        'studio',
        'add-entity',
        file.path,
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, 'Added entity to ${file.path}.\n');
    });

    test('unknown component: prints error to stderr and exits 1', () async {
      final file = _level(_empty);
      final result = await runStudioCapture([
        'studio',
        'add-entity',
        file.path,
        '--component',
        'warpDrive',
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('unknown component'));
    });
  });

  group('remove-entity', () {
    test('prints removed entity message', () async {
      final file = _level(_withPlayer);
      final result = await runStudioCapture([
        'studio',
        'remove-entity',
        file.path,
        '--entity',
        'player',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, 'Removed entity player from ${file.path}.\n');
    });

    test('missing entity: prints error to stderr and exits 1', () async {
      final file = _level(_withPlayer);
      final result = await runStudioCapture([
        'studio',
        'remove-entity',
        file.path,
        '--entity',
        'nobody',
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('no entity named'));
    });
  });

  group('set-field', () {
    test('prints set field message', () async {
      final file = _level(_withPlayer);
      final result = await runStudioCapture([
        'studio',
        'set-field',
        file.path,
        '--entity',
        'player',
        '--component',
        'position',
        '--field',
        'x',
        '--value',
        '99',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, 'Set player.position.x in ${file.path}.\n');
    });

    test('invalid value: prints error to stderr and exits 1', () async {
      final file = _level(_withPlayer);
      final result = await runStudioCapture([
        'studio',
        'set-field',
        file.path,
        '--entity',
        'player',
        '--component',
        'position',
        '--field',
        'x',
        '--value',
        '"not a number"',
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('would make'));
      expect(result.stderr, contains('x must be a number'));
    });
  });

  group('move-entity', () {
    test('prints moved entity message', () async {
      final file = _level(_withPlayer);
      final result = await runStudioCapture([
        'studio',
        'move-entity',
        file.path,
        '--entity',
        'player',
        '--x',
        '40',
        '--y',
        '50',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, 'Moved player to (40.0, 50.0) in ${file.path}.\n');
    });
  });

  group('set-layer', () {
    test('prints set layer message', () async {
      final file = _level('''
{
  "entities": [
    {"name": "coin", "components": {"sprite": {"atlasId": "a", "region": "r"}}}
  ]
}
''');
      final result = await runStudioCapture([
        'studio',
        'set-layer',
        file.path,
        '--entity',
        'coin',
        '--component',
        'sprite',
        '--z-index',
        '5',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, 'Set coin.sprite.zIndex to 5 in ${file.path}.\n');
    });
  });

  group('paint-tile', () {
    test('prints paint tile message', () async {
      final file = _level(_withTileMap);
      final result = await runStudioCapture([
        'studio',
        'paint-tile',
        file.path,
        '--entity',
        'map',
        '--col',
        '0',
        '--row',
        '0',
        '--tile-id',
        '1',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, 'Set tile (0, 0) to 1 on map in ${file.path}.\n');
    });
  });

  group('fill-region', () {
    test('prints fill region message', () async {
      final file = _level(_withTileMap);
      final result = await runStudioCapture([
        'studio',
        'fill-region',
        file.path,
        '--entity',
        'map',
        '--col',
        '0',
        '--row',
        '0',
        '--tile-id',
        '2',
      ]);
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        'Filled region at (0, 0) with 2 on map in ${file.path}.\n',
      );
    });
  });

  group('import-tmx', () {
    test('prints written path with dimensions', () async {
      final dir = Directory.systemTemp.createTempSync('studio_import_golden');
      addTearDown(() => dir.deleteSync(recursive: true));

      const tmx = '''
<map version="1.10" orientation="orthogonal" width="2" height="2" tilewidth="10" tileheight="10">
 <tileset firstgid="1" name="tiles" tilewidth="10" tileheight="10" tilecount="2" columns="2">
   <image source="tiles.png" width="20" height="10"/>
   <tile id="0"><properties><property name="solid" type="bool" value="true"/></properties></tile>
 </tileset>
 <layer id="1" name="Tile Layer 1" width="2" height="2">
  <data encoding="csv">
  0,1,
  1,0,
  </data>
 </layer>
</map>
''';
      final tmxFile = File('${dir.path}/map.tmx')..writeAsStringSync(tmx);
      final result = await runStudioCapture([
        'studio',
        'import-tmx',
        tmxFile.path,
        '--project',
        dir.path,
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Wrote'));
      expect(result.stdout, contains('2x2 tiles'));
    });
  });

  group('export-levels', () {
    test('prints written message for each level', () async {
      final project = _project(_withPlayer, name: 'main.level.json');
      final result = await runStudioCapture([
        'studio',
        'export-levels',
        project.path,
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('written in canonical form'));
    });
  });

  group('project-manifest', () {
    test('prints written message with level count', () async {
      final dir = Directory.systemTemp.createTempSync('studio_manifest');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: test_game\n');
      final levels = Directory('${dir.path}/assets/levels')
        ..createSync(recursive: true);
      File('${levels.path}/main.level.json').writeAsStringSync(_withPlayer);

      final result = await runStudioCapture([
        'studio',
        'project-manifest',
        dir.path,
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Wrote'));
      expect(result.stdout, contains('1 level(s)'));
    });
  });
}
