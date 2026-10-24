import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/idle_command.dart';
import 'package:engine_cli/src/ops_cli.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

class Run {
  Run(this.code, this.out, this.err);
  final int code;
  final String out, err;
  Map<String, dynamic> get json => jsonDecode(out) as Map<String, dynamic>;
}

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('ops_cli');
    File(
      '${project.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nversion: 1.0.0\n');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
    File('${project.path}/assets/levels/a.json').writeAsStringSync(
      '{"entities": [{"name": "player", "components": {"position": {"x": 1, "y": 2}}}]}',
    );
  });
  tearDown(() => project.deleteSync(recursive: true));

  Future<Run> run(
    List<String> args, {
    String? stdinText,
    bool withProject = true,
  }) async {
    final out = StringBuffer(), err = StringBuffer();
    final runner = CommandRunner<int>('game_agent', 'test')
      ..addCommand(IdleCommand(out: out));
    addOperationCommands(
      runner,
      buildRegistry(),
      io: CliIo(
        out: out,
        err: err,
        stdinStream: Stream.value(utf8.encode(stdinText ?? '')),
      ),
    );
    final code =
        await runner.run([
          if (withProject) ...['--project', project.path],
          ...args,
        ]) ??
        0;
    return Run(code, out.toString(), err.toString());
  }

  test(
    'every operation has a command with working --help (1:1, generated from the registry)',
    () async {
      final registry = buildRegistry();
      for (final op in registry.all) {
        final r = await run([
          op.cli.group ?? op.group,
          op.cli.verb ?? op.verb.replaceAll('_', '-'),
          '--help',
        ], withProject: false);
        expect(r.code, 0, reason: op.name);
      }
    },
  );

  test('reads print text or the exact JSON envelope', () async {
    final text = await run(['project', 'info']);
    expect(text.code, 0);
    expect(text.out, contains('"name": "demo"'));
    final j = await run(['level', 'list', '--json']);
    expect(j.code, 0);
    expect(j.json['ok'], true);
    expect((j.json['data'] as List).single['path'], 'assets/levels/a.json');
  });

  test(
    'positional arguments, typed flags and arrays reach the operation',
    () async {
      final r = await run([
        'level',
        'read',
        'assets/levels/a.json',
        '--entity',
        'player',
        '--components',
        'position',
        '--entity-limit',
        '5',
        '--json',
      ]);
      expect(r.code, 0, reason: r.err);
      final entities = (r.json['data'] as Map)['entities'] as List;
      expect(entities.single['name'], 'player');
    },
  );

  test('--args and --stdin supply parameters; flags win', () async {
    final a = await run([
      'level',
      'read',
      '--args',
      '{"path": "assets/levels/a.json"}',
      '--json',
    ]);
    expect(a.code, 0, reason: a.err);
    final s = await run([
      'level',
      'read',
      '--stdin',
      '--json',
    ], stdinText: '{"path": "assets/levels/a.json", "entity": "ghost"}');
    expect(s.code, ErrorCode.notFound.exit);
    final w = await run([
      'level',
      'read',
      '--stdin',
      '--entity',
      'player',
      '--json',
    ], stdinText: '{"path": "assets/levels/a.json", "entity": "ghost"}');
    expect(w.code, 0, reason: 'the flag beats stdin');
    final bad = await run(['level', 'read', '--args', 'not json']);
    expect(bad.code, ErrorCode.invalidParams.exit);
  });

  test(
    'errors go to stderr with the exit code of their error code, and --json keeps them on stdout',
    () async {
      final r = await run(['level', 'read', 'assets/levels/missing.json']);
      expect(r.code, 66);
      expect(r.err, contains('Error (not_found)'));
      final j = await run([
        'level',
        'read',
        'assets/levels/missing.json',
        '--json',
      ]);
      expect(j.json['ok'], false);
      expect((j.json['error'] as Map)['code'], 'not_found');
      final inval = await run(['level', 'read', '../x.json']);
      expect(inval.code, 64);
      final problems = await run([
        'idle',
        'validate-json',
      ]).catchError((Object _) => Run(-1, '', ''));
      expect(problems.code, isNot(0));
    },
  );

  test('validation commands exit 1 when the thing is invalid', () async {
    File('${project.path}/assets/levels/bad.json').writeAsStringSync(
      '{"entities": [{"name": "x", "components": {"position": {"x": "left", "y": 0}}}]}',
    );
    expect((await run(['level', 'validate', 'assets/levels/a.json'])).code, 0);
    expect(
      (await run(['level', 'validate', 'assets/levels/bad.json'])).code,
      1,
    );
    expect((await run(['project', 'validate'])).code, 1);
  });

  test('--read-only and the project flag are global', () async {
    final r = await run(['--read-only', 'undo', 'undo']);
    expect(r.code, ErrorCode.readOnly.exit);
    final none = await run(['project', 'info'], withProject: false);
    expect(
      none.code,
      isNot(0),
      reason: 'no project found from the working directory of this test',
    );
  });

  test(
    'existing groups keep their hand-written verbs and gain the new ones',
    () async {
      final r = await run(['idle', 'format-number', '1234567']);
      expect(r.code, 0, reason: r.err);
      expect(r.out, contains('1.23M'));
      final legacy = await run(['idle', 'validate', '--help']);
      expect(legacy.code, 0);
    },
  );

  test('a call without a required parameter says which', () async {
    final r = await run(['schema', 'component']);
    expect(r.code, 64);
    expect(r.err, contains('"name" is required'));
  });
}
