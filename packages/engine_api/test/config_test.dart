import 'dart:convert';
import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:test/test.dart';

void main() {
  test('every key becomes the matching flag', () {
    final args = configToArgs('''
project: .
readOnly: true
bind: 127.0.0.1
port: 7500
allowedOrigins: [https://a.example]
operations:
  allow: ["level.*"]
  deny: ["release.*"]
limits:
  maxResultBytes: 1000
  requestsPerMinute: 30
log:
  file: .studio/x.jsonl
  level: debug
''');
    expect(args, [
      '--project',
      '.',
      '--read-only',
      '--bind',
      '127.0.0.1',
      '--port',
      '7500',
      '--allow-origin',
      'https://a.example',
      '--allow',
      'level.*',
      '--deny',
      'release.*',
      '--max-result-bytes',
      '1000',
      '--requests-per-minute',
      '30',
      '--log',
      '.studio/x.jsonl',
      '--log-level',
      'debug',
    ]);
  });

  test('unknown log keys are rejected', () {
    expect(
      () => configToArgs('log:\n  path: x.jsonl\n'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('unknown keys and wrong shapes are errors, empty is fine', () {
    expect(
      () => configToArgs('readonly: true'),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => configToArgs('limits: {nope: 1}'),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => configToArgs('operations: {block: []}'),
      throwsA(isA<ConfigException>()),
    );
    expect(() => configToArgs('- a\n- b'), throwsA(isA<ConfigException>()));
    expect(() => configToArgs('a: [unclosed'), throwsA(isA<ConfigException>()));
    expect(configToArgs(''), isEmpty);
  });

  group('through the server', () {
    late Directory project;
    setUp(() {
      project = Directory.systemTemp.createTempSync('cfg');
      File('${project.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
      Directory('${project.path}/assets/levels').createSync(recursive: true);
      File('${project.path}/assets/levels/a.json').writeAsStringSync(
        '{"entities": [{"name": "p", "components": {"position": {"x": 1, "y": 2}}}]}',
      );
    });
    tearDown(() => project.deleteSync(recursive: true));

    Future<List<Map>> ask(
      List<String> flags,
      List<Map<String, Object?>> reqs, [
      List<String>? errs,
    ]) async {
      final out = <String>[];
      final code = await runServer(
        flags,
        input: Stream.value(
          utf8.encode('${reqs.map(jsonEncode).join('\n')}\n'),
        ),
        write: out.add,
        err: (l) => errs?.add(l),
      );
      expect(code, 0, reason: '${errs ?? ''}');
      return [for (final l in out) jsonDecode(l) as Map];
    }

    test(
      'engine_api.yaml next to the project applies and flags override it',
      () async {
        File(
          '${project.path}/engine_api.yaml',
        ).writeAsStringSync('readOnly: true\n');
        final move = {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'level.move_entity',
            'arguments': {
              'path': 'assets/levels/a.json',
              'name': 'p',
              'x': 3,
              'y': 3,
            },
          },
        };
        final denied =
            (await ask(['--project', project.path], [move])).single['result']
                as Map;
        expect(
          ((denied['structuredContent'] as Map)['error'] as Map)['code'],
          'read_only',
        );
      },
    );

    test(
      'a bad config stops the server with exit code 78 and says why',
      () async {
        File('${project.path}/engine_api.yaml').writeAsStringSync('nope: 1\n');
        final errs = <String>[];
        final code = await runServer(
          ['--project', project.path],
          input: const Stream.empty(),
          write: (_) {},
          err: errs.add,
        );
        expect(code, 78);
        expect(errs.single, contains('Unknown key "nope"'));
        expect(
          await runServer(
            ['--config', '${project.path}/missing.yaml'],
            input: const Stream.empty(),
            write: (_) {},
            err: (_) {},
          ),
          78,
        );
      },
    );
  });
}
