import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/idle_command.dart';
import 'package:test/test.dart';

const _game = '''
{
  "resources": { "coins": { "start": "15" } },
  "generators": [
    { "id": "cursor", "cost": { "type": "geometric", "base": "15", "growth": 1.15 }, "output": { "coins": "0.5" } }
  ]
}
''';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('idle_cmd_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(int, String)> run(List<String> args) async {
    final out = StringBuffer();
    final runner = CommandRunner<int>('game_agent', 'test')
      ..addCommand(IdleCommand(out: out));
    final code = await runner.run(['idle', 'simulate', ...args]) ?? 0;
    return (code, out.toString());
  }

  test('prints a deterministic pacing report for a valid game', () async {
    final f = File('${tmp.path}/g.json')..writeAsStringSync(_game);
    final (code, a) = await run([f.path, '--days', '1']);
    final (_, b) = await run([f.path, '--days', '1']);
    expect(code, 0);
    expect(a, startsWith('Simulated '));
    expect(a, contains('income reaches 1e0 coins/s'));
    expect(a, contains('Final income:'));
    expect(a, b, reason: 'same input, same report');
  });

  test('a definition with problems exits 1 and prints nothing', () async {
    final f = File('${tmp.path}/bad.json')
      ..writeAsStringSync('{"generators": [{"id": "x"}]}');
    final (code, out) = await run([f.path]);
    expect(code, 1);
    expect(out, isEmpty);
  });

  test('missing file and bad options are refused', () async {
    expect((await run(['${tmp.path}/nope.json'])).$1, 1);
    final f = File('${tmp.path}/g.json')..writeAsStringSync(_game);
    expect(() => run([f.path, '--days', 'x']), throwsA(isA<UsageException>()));
    expect(() => run([]), throwsA(isA<UsageException>()));
  });

  group('validate', () {
    Future<(int, String)> check(List<String> args) async {
      final out = StringBuffer();
      final runner = CommandRunner<int>('game_agent', 'test')
        ..addCommand(IdleCommand(out: out));
      final code = await runner.run(['idle', 'validate', ...args]) ?? 0;
      return (code, out.toString());
    }

    test('a valid game says OK with its size and exits 0', () async {
      final f = File('${tmp.path}/g.json')..writeAsStringSync(_game);
      final (code, out) = await check([f.path]);
      expect(code, 0);
      expect(out, contains('OK (1 generators, 0 upgrades)'));
    });

    test(
      'every problem is listed with its path and the exit code is 1',
      () async {
        final f = File('${tmp.path}/bad.json')
          ..writeAsStringSync(
            '{"generators": [{"id": "a", "cost": {"type": "geometric", "base": "1", "growth": 0.5}}, {"id": "a", "cost": {"type": "table", "prices": []}}]}',
          );
        final (code, out) = await check([f.path]);
        expect(code, 1);
        expect(
          out,
          contains('generators[0].cost.growth must be a number >= 1'),
        );
        expect(out, contains('generators[1].id "a" is used twice'));
        expect(
          out,
          contains('generators[1].cost.prices must be a non-empty list'),
        );
      },
    );

    test('a missing or non-JSON file is an error, not a crash', () async {
      expect((await check(['${tmp.path}/nope.json'])).$1, 1);
      final f = File('${tmp.path}/x.json')..writeAsStringSync('not json');
      expect((await check([f.path])).$1, 1);
      expect(() => check([]), throwsA(isA<UsageException>()));
    });
  });
}
