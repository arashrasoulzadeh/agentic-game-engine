import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/studio_command.dart';
import 'package:test/test.dart';

/// Runs `game_agent studio validate` against a throwaway project and returns
/// its exit code. stdout is discarded here: these tests check the exit code,
/// which is the contract CI relies on.
Future<int> _validate(Directory project, {bool strict = false}) async {
  final runner = CommandRunner<int>('game_agent', 'test')
    ..addCommand(StudioCommand());
  final args = ['studio', 'validate', project.path, if (strict) '--strict'];
  return await IOOverrides.runZoned(
    () async => (await runner.run(args)) ?? 0,
    stdout: () => _NullStdout(),
  );
}

class _NullStdout implements Stdout {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  void writeln([Object? object = '']) {}
  @override
  void write(Object? object) {}
}

Directory _project(String levelJson, {String name = 'level.json'}) {
  final dir = Directory.systemTemp.createTempSync('studio_validate');
  final levels = Directory('${dir.path}/assets/levels')
    ..createSync(recursive: true);
  File('${levels.path}/$name').writeAsStringSync(levelJson);
  return dir;
}

const _valid = '''
{
  "entities": [
    {"name": "player", "components": {"position": {"x": 10, "y": 20}}}
  ]
}
''';

const _invalid = '''
{
  "entities": [
    {"name": "player", "components": {"position": {"x": "left", "y": 0}}}
  ]
}
''';

void main() {
  test('exits 0 for a project whose levels are all valid', () async {
    final project = _project(_valid);
    addTearDown(() => project.deleteSync(recursive: true));
    expect(await _validate(project), 0);
  });

  test('exits 1 when a level has an error', () async {
    final project = _project(_invalid);
    addTearDown(() => project.deleteSync(recursive: true));
    expect(await _validate(project), 1);
  });

  test('exits 1 when a level is not valid JSON', () async {
    final project = _project('{ not json');
    addTearDown(() => project.deleteSync(recursive: true));
    expect(await _validate(project), 1);
  });

  test('exits 1 when the project has no assets/levels folder', () async {
    final project = Directory.systemTemp.createTempSync(
      'studio_validate_empty',
    );
    addTearDown(() => project.deleteSync(recursive: true));
    expect(await _validate(project), 1);
  });

  group('--strict', () {
    // A wall of solid tiles the full height of the map: the exit is a warning,
    // not an error, because the reachability check is a heuristic.
    const walled = '''
{
  "entities": [
    {"name": "map", "components": {
      "position": {"x": 0, "y": 0},
      "tileMap": {
        "tileWidth": 10, "tileHeight": 10,
        "legend": {".": 0, "#": 1},
        "rows": ["..#..", "..#..", "#####"]
      }
    }},
    {"name": "player", "components": {"position": {"x": 15, "y": 15}}},
    {"name": "exit", "components": {
      "position": {"x": 45, "y": 15},
      "roomExit": {"targetSceneId": "next", "spawnPoint": "entrance"}
    }}
  ]
}
''';

    test('a warning alone exits 0', () async {
      final project = _project(walled);
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _validate(project), 0);
    });

    test('a warning exits 1 with --strict', () async {
      final project = _project(walled);
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _validate(project, strict: true), 1);
    });
  });
}
