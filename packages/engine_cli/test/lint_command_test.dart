import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/lint_command.dart';
import 'package:test/test.dart';

Future<int> _runLint(List<String> args) async {
  final runner = CommandRunner<int>('game_agent', 'test')
    ..addCommand(LintCommand());
  return (await runner.run(['lint', ...args])) ?? 0;
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('lint_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('returns 0 for a valid level file', () async {
    final file = File('${tmp.path}/level.json')
      ..writeAsStringSync('{"entities": [{"components": {"position": {"x": 1, "y": 2}}}]}');

    expect(await _runLint([file.path]), 0);
  });

  test('returns 1 and reports the specific error for an invalid level file', () async {
    final file = File('${tmp.path}/level.json')
      ..writeAsStringSync('{"entities": "not a list"}');

    expect(await _runLint([file.path]), 1);
  });

  test('returns 1 for malformed JSON', () async {
    final file = File('${tmp.path}/level.json')..writeAsStringSync('{not json');

    expect(await _runLint([file.path]), 1);
  });

  test('returns 1 when the file does not exist', () async {
    expect(await _runLint(['${tmp.path}/missing.json']), 1);
  });

  group('--render', () {
    test('returns 1 when the level has no tileMap component', () async {
      final file = File('${tmp.path}/level.json')
        ..writeAsStringSync('{"entities": [{"components": {"position": {"x": 1, "y": 2}}}]}');

      expect(await _runLint([file.path, '--render', '${tmp.path}/out.png']), 1);
    });

    test('writes a PNG sized to the TileMap grid when one is present', () async {
      final file = File('${tmp.path}/level.json')
        ..writeAsStringSync(jsonEncodeLevel);
      final outPath = '${tmp.path}/out.png';

      expect(await _runLint([file.path, '--render', outPath]), 0);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue);
      // PNG signature bytes.
      final bytes = outFile.readAsBytesSync();
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    test('does not render when --render is not passed', () async {
      final file = File('${tmp.path}/level.json')..writeAsStringSync(jsonEncodeLevel);

      expect(await _runLint([file.path]), 0);
      expect(File('${tmp.path}/out.png').existsSync(), isFalse);
    });
  });
}

const jsonEncodeLevel = '''
{
  "entities": [
    {
      "name": "tileMap",
      "components": {
        "position": {"x": 0, "y": 0},
        "tileMap": {
          "tileWidth": 40, "tileHeight": 40,
          "legend": {".": 0, "#": 1},
          "rows": ["...", "###"],
          "solidTileIds": [1]
        }
      }
    },
    {
      "name": "player",
      "components": {"position": {"x": 20, "y": 20}}
    }
  ]
}
''';
