import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/run_studio.dart';

File _level(String json) {
  final dir = Directory.systemTemp.createTempSync('studio_edit');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/level.json')..writeAsStringSync(json);
  return file;
}

Map<String, dynamic> _read(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

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
  group('add-entity', () {
    test('adds a named entity with no components', () async {
      final file = _level(_empty);
      expect(await runStudio(['add-entity', file.path, '--name', 'coin']), 0);
      final entities = _read(file)['entities'] as List;
      expect(entities.single['name'], 'coin');
    });

    test('a --component starts at its schema defaults', () async {
      final file = _level(_empty);
      expect(
        await runStudio(['add-entity', file.path, '--component', 'pushable']),
        0,
      );
      final entity = (_read(file)['entities'] as List).single as Map;
      final components = entity['components'] as Map;
      expect(components.containsKey('pushable'), isTrue);
    });

    test('an unknown component is rejected and nothing is written', () async {
      final file = _level(_empty);
      final before = file.readAsStringSync();
      expect(
        await runStudio(['add-entity', file.path, '--component', 'warpDrive']),
        1,
      );
      expect(file.readAsStringSync(), before);
    });
  });

  group('remove-entity', () {
    test('removes the named entity', () async {
      final file = _level(_withPlayer);
      expect(
        await runStudio(['remove-entity', file.path, '--entity', 'player']),
        0,
      );
      expect(_read(file)['entities'], isEmpty);
    });

    test('a missing entity name exits 1 and writes nothing', () async {
      final file = _level(_withPlayer);
      final before = file.readAsStringSync();
      expect(
        await runStudio(['remove-entity', file.path, '--entity', 'nobody']),
        1,
      );
      expect(file.readAsStringSync(), before);
    });
  });

  group('set-field', () {
    test('sets a field, parsing the value as JSON', () async {
      final file = _level(_withPlayer);
      expect(
        await runStudio([
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
        ]),
        0,
      );
      final entity = (_read(file)['entities'] as List).single as Map;
      final position = (entity['components'] as Map)['position'] as Map;
      expect(position['x'], 99);
    });

    test('a plain-string value that is not JSON is kept as a string', () async {
      final file = _level('''
{
  "entities": [
    {"name": "player", "components": {
      "position": {"x": 1, "y": 2},
      "roomExit": {"targetSceneId": "start", "spawnPoint": "entrance"}
    }}
  ]
}
''');
      expect(
        await runStudio([
          'set-field',
          file.path,
          '--entity',
          'player',
          '--component',
          'roomExit',
          '--field',
          'targetSceneId',
          '--value',
          'cave',
        ]),
        0,
      );
      final entity = (_read(file)['entities'] as List).single as Map;
      final roomExit = (entity['components'] as Map)['roomExit'] as Map;
      expect(roomExit['targetSceneId'], 'cave');
    });

    test(
      'a value that makes the level invalid is rejected, nothing written',
      () async {
        final file = _level(_withPlayer);
        final before = file.readAsStringSync();
        expect(
          await runStudio([
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
          ]),
          1,
        );
        expect(file.readAsStringSync(), before);
      },
    );
  });

  group('move-entity', () {
    test('sets the position component', () async {
      final file = _level(_withPlayer);
      expect(
        await runStudio([
          'move-entity',
          file.path,
          '--entity',
          'player',
          '--x',
          '40',
          '--y',
          '50',
        ]),
        0,
      );
      final entity = (_read(file)['entities'] as List).single as Map;
      final position = (entity['components'] as Map)['position'] as Map;
      expect(position, {'x': 40.0, 'y': 50.0});
    });

    test('a non-numeric --x is rejected', () async {
      final file = _level(_withPlayer);
      expect(
        await runStudio([
          'move-entity',
          file.path,
          '--entity',
          'player',
          '--x',
          'left',
          '--y',
          '50',
        ]),
        1,
      );
    });
  });

  group('set-layer', () {
    test('sets zIndex on an existing component', () async {
      final file = _level('''
{
  "entities": [
    {"name": "coin", "components": {
      "sprite": {"atlasId": "a", "region": "r"}
    }}
  ]
}
''');
      expect(
        await runStudio([
          'set-layer',
          file.path,
          '--entity',
          'coin',
          '--component',
          'sprite',
          '--z-index',
          '5',
        ]),
        0,
      );
      final entity = (_read(file)['entities'] as List).single as Map;
      final sprite = (entity['components'] as Map)['sprite'] as Map;
      expect(sprite['zIndex'], 5);
    });

    test('a component the entity does not have is rejected', () async {
      final file = _level(_withPlayer);
      expect(
        await runStudio([
          'set-layer',
          file.path,
          '--entity',
          'player',
          '--component',
          'sprite',
          '--z-index',
          '1',
        ]),
        1,
      );
    });
  });

  group('paint-tile', () {
    test('sets one tile, flattening a legend-authored map first', () async {
      final file = _level(_withTileMap);
      expect(
        await runStudio([
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
        ]),
        0,
      );
      final entity = (_read(file)['entities'] as List).single as Map;
      final tileMap = (entity['components'] as Map)['tileMap'] as Map;
      expect(tileMap.containsKey('tiles'), isTrue);
      expect((tileMap['tiles'] as List).first, 1);
    });

    test('an entity with no tileMap is rejected', () async {
      final file = _level(_withPlayer);
      expect(
        await runStudio([
          'paint-tile',
          file.path,
          '--entity',
          'player',
          '--col',
          '0',
          '--row',
          '0',
          '--tile-id',
          '1',
        ]),
        1,
      );
    });
  });

  group('fill-region', () {
    test('fills the connected region at (col, row)', () async {
      final file = _level(_withTileMap);
      expect(
        await runStudio([
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
        ]),
        0,
      );
      final entity = (_read(file)['entities'] as List).single as Map;
      final tileMap = (entity['components'] as Map)['tileMap'] as Map;
      expect(tileMap['tiles'], everyElement(2));
    });
  });

  test('missing the level file argument exits 1', () async {
    expect(await runStudio(['add-entity']), 1);
  });
}
