import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/run_studio.dart';

/// Runs the commands of docs/studio/first-level.md in order, so the tutorial cannot drift from the CLI.
void main() {
  test('the first-level tutorial steps work and the level validates', () async {
    final dir = Directory.systemTemp.createTempSync('first_level');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/assets/levels').createSync(recursive: true);
    final level = File('${dir.path}/assets/levels/level1.json')
      ..writeAsStringSync('{"entities": []}');
    final path = level.path;

    Future<int> setField(
      String entity,
      String component,
      String field,
      String value,
    ) => runStudio([
      'set-field',
      path,
      '--entity',
      entity,
      '--component',
      component,
      '--field',
      field,
      '--value',
      value,
    ]);

    expect(
      await runStudio([
        'add-entity',
        path,
        '--name',
        'ground',
        '--component',
        'position',
        '--component',
        'tileMap',
      ]),
      0,
    );
    for (final f in [
      ['cols', '8'],
      ['rows', '3'],
      ['tileWidth', '16'],
      ['tileHeight', '16'],
      ['solidTileIds', '[1]'],
      ['tiles', '[0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1]'],
    ]) {
      expect(await setField('ground', 'tileMap', f[0], f[1]), 0, reason: f[0]);
    }
    expect(
      await runStudio([
        'paint-tile',
        path,
        '--entity',
        'ground',
        '--col',
        '3',
        '--row',
        '1',
        '--tile-id',
        '1',
      ]),
      0,
    );
    expect(
      await runStudio([
        'add-entity',
        path,
        '--name',
        'player',
        '--component',
        'position',
      ]),
      0,
    );
    expect(await setField('player', 'position', 'x', '24'), 0);
    expect(await setField('player', 'position', 'y', '16'), 0);

    final entities = (jsonDecode(level.readAsStringSync())['entities'] as List)
        .cast<Map<String, dynamic>>();
    expect(entities.map((e) => e['name']), ['ground', 'player']);
    final tiles =
        (entities.first['components'] as Map)['tileMap']['tiles'] as List;
    expect(tiles[1 * 8 + 3], 1, reason: 'the painted step');
    expect(tiles[2 * 8 + 5], 1, reason: 'the floor');
    expect((entities.last['components'] as Map)['position']['x'], 24);
    expect(await runStudio(['validate', dir.path]), 0);
  });
}
