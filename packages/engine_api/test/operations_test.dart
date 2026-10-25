import 'dart:convert';
import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('api_ops');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
    File('${project.path}/assets/levels/a.json').writeAsStringSync(
      '{"entities": [{"name": "player", "components": {"position": {"x": 1, "y": 2}}}]}',
    );
  });
  tearDown(() => project.deleteSync(recursive: true));

  McpSession session({RequestLog? log, int max = 8 * 1024 * 1024}) =>
      McpSession(
        buildRegistry(),
        OpContext(project: ProjectRoot(project.path), actor: 'test'),
        log: log,
        maxResultBytes: max,
      );

  test(
    'every call is logged as one JSON line without arguments or results',
    () async {
      final path = '${project.path}/log.jsonl';
      final s = session(log: RequestLog(path));
      await s.invoke('level.list', {}, transport: 'rest', requestId: 'r1');
      await s.invoke('level.read', {'path': 'assets/levels/none.json'});
      final lines = File(
        path,
      ).readAsLinesSync().map(jsonDecode).cast<Map>().toList();
      expect(lines, hasLength(2));
      expect(lines[0], containsPair('op', 'level.list'));
      expect(lines[0], containsPair('transport', 'rest'));
      expect(lines[0], containsPair('requestId', 'r1'));
      expect(lines[0], containsPair('ok', true));
      expect(lines[0], containsPair('kind', 'read'));
      expect(lines[0], containsPair('bytesIn', isA<int>()));
      expect(lines[1], containsPair('ok', false));
      expect(lines[1], containsPair('code', 'not_found'));
      expect(jsonEncode(lines), isNot(contains('none.json')));
      expect(jsonEncode(lines), isNot(contains('player')));
      expect(jsonEncode(lines), isNot(contains('"args"')));
    },
  );

  test('debug level logs redacted args; logging/setLevel switches it', () async {
    final path = '${project.path}/log.jsonl';
    final sink = RequestLog(path, level: RequestLogLevel.debug);
    final s = session(log: sink);
    await s.invoke('level.read', {'path': 'assets/levels/a.json'});
    final debugLine =
        jsonDecode(File(path).readAsLinesSync().single) as Map;
    expect(debugLine['args'], {'path': 'assets/levels/a.json'});

    await s.dispatch('logging/setLevel', {'level': 'info'});
    expect(sink.level, RequestLogLevel.info);
    File(path).writeAsStringSync('');
    await s.invoke('level.read', {'path': 'assets/levels/a.json'});
    expect(
      jsonDecode(File(path).readAsLinesSync().single) as Map,
      isNot(contains('args')),
    );

    await s.dispatch('logging/setLevel', {'level': 'debug'});
    expect(sink.level, RequestLogLevel.debug);
  });

  test('debug args redact Param.secret values', () {
    expect(
      redactArgs(
        Operation(
          name: 't.secret',
          summary: 'x',
          description: 'x',
          kind: OperationKind.read,
          scope: OperationScope.pure,
          params: const [
            Param('token', ParamType.string, secret: true),
            Param('name', ParamType.string),
          ],
          handler: (c, a) => OpOutcome.data({}),
        ),
        {'token': 'hunter2', 'name': 'Ada'},
      ),
      {'token': '***', 'name': 'Ada'},
    );
  });

  test('a write records its undoId', () async {
    final path = '${project.path}/log.jsonl';
    await session(log: RequestLog(path)).invoke('level.move_entity', {
      'path': 'assets/levels/a.json',
      'name': 'player',
      'x': 2,
      'y': 2,
    });
    expect(
      jsonDecode(File(path).readAsLinesSync().single)['undoId'],
      isNotNull,
    );
  });

  test(
    'results over the limit become too_large instead of flooding the client',
    () async {
      final r = await session(max: 100).invoke('engine.operations', {});
      expect(r.error!.code, ErrorCode.tooLarge);
      expect((await session().invoke('engine.operations', {})).ok, isTrue);
    },
  );

  test('the log rotates at its size limit and keeps a bounded history', () {
    final path = '${project.path}/rot.jsonl';
    final log = RequestLog(path, maxBytes: 50, keep: 2);
    for (var i = 0; i < 12; i++) {
      log.write({'n': i, 'pad': 'x' * 30});
    }
    expect(File('$path.1').existsSync(), isTrue);
    expect(File('$path.2').existsSync(), isTrue);
    expect(File('$path.3').existsSync(), isFalse);
    expect(File(path).readAsLinesSync().last, contains('"n":11'));
  });

  test('HTTP rate limit answers 429 with Retry-After', () async {
    final server = await EngineHttpServer.start(
      session(),
      token: 't',
      requestsPerMinute: 2,
    );
    addTearDown(server.close);
    final client = HttpClient();
    Future<HttpClientResponse> hit() async {
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/v1/level/list'),
      );
      req.headers.set('authorization', 'Bearer t');
      final res = await req.close();
      await res.drain<void>();
      return res;
    }

    expect((await hit()).statusCode, 200);
    expect((await hit()).statusCode, 200);
    final limited = await hit();
    expect(limited.statusCode, 429);
    expect(limited.headers.value('retry-after'), '1');
  });
}
