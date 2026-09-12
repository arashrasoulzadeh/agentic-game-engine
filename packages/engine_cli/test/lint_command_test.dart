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
}
