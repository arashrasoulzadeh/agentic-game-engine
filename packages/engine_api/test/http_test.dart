import 'dart:convert';
import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

const token = 'secret-token';

class Reply {
  Reply(this.status, this.body, this.headers);
  final int status;
  final dynamic body;
  final HttpHeaders headers;
}

void main() {
  late Directory project;
  late EngineHttpServer server;
  final client = HttpClient();

  Future<EngineHttpServer> start({
    bool readOnly = false,
    int maxBytes = 1048576,
  }) => EngineHttpServer.start(
    McpSession(
      buildRegistry(),
      OpContext(
        project: ProjectRoot(project.path),
        policy: Policy(readOnly: readOnly),
      ),
    ),
    token: token,
    maxRequestBytes: maxBytes,
  );

  setUp(() async {
    project = Directory.systemTemp.createTempSync('http_api');
    File(
      '${project.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nversion: 1.0.0\n');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
    File('${project.path}/assets/levels/a.json').writeAsStringSync(
      '{"entities": [{"name": "player", "components": {"position": {"x": 1, "y": 2}}}]}',
    );
    server = await start();
  });
  tearDown(() async {
    await server.close();
    project.deleteSync(recursive: true);
  });

  Future<Reply> send(
    String method,
    String path, {
    Object? body,
    String? auth = 'Bearer $token',
    Map<String, String> headers = const {},
  }) async {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (auth != null) req.headers.set('authorization', auth);
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(body is String ? body : jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return Reply(
      res.statusCode,
      text.isEmpty ? null : jsonDecode(text),
      res.headers,
    );
  }

  test('health needs no token and reveals no project data', () async {
    final r = await send('GET', '/v1/health', auth: null);
    expect(r.status, 200);
    expect(r.body['status'], 'ok');
    expect(jsonEncode(r.body), isNot(contains('demo')));
  });

  test('everything else needs the bearer token', () async {
    expect((await send('POST', '/v1/level/list', auth: null)).status, 401);
    expect(
      (await send('POST', '/v1/level/list', auth: 'Bearer nope')).status,
      401,
    );
    expect((await send('POST', '/rpc', auth: 'Basic x', body: {})).status, 401);
    expect((await send('POST', '/v1/level/list')).status, 200);
  });

  test(
    'REST runs an operation and maps error codes to HTTP statuses',
    () async {
      final ok = await send('POST', '/v1/level/list');
      expect(ok.body['ok'], true);
      expect(ok.body['data'][0]['path'], 'assets/levels/a.json');
      final missing = await send(
        'POST',
        '/v1/level/read',
        body: {'path': 'assets/levels/x.json'},
      );
      expect(missing.status, 404);
      expect(missing.body['error']['code'], 'not_found');
      final invalid = await send('POST', '/v1/level/read', body: {});
      expect(invalid.status, 400);
      expect((await send('POST', '/v1/level/read', body: '[1]')).status, 400);
      expect((await send('POST', '/v1/level/read', body: '{nope')).status, 400);
    },
  );

  test(
    'REST accepts hyphenated verbs, rejects unknown paths and wrong methods',
    () async {
      expect(
        (await send(
          'POST',
          '/v1/level/lock-status',
          body: {'path': 'assets/levels/a.json'},
        )).status,
        200,
      );
      expect((await send('POST', '/v1/nope/nothing')).status, 404);
      expect(
        (await send('POST', '/v1/project/create')).status,
        404,
        reason: 'Flutter operations are not served',
      );
      final get = await send('GET', '/v1/level/list');
      expect(get.status, 405);
      expect(get.headers.value('allow'), 'POST');
      expect((await send('GET', '/elsewhere')).status, 404);
    },
  );

  test(
    'REST writes change files; read-only servers refuse them with 403',
    () async {
      final w = await send(
        'POST',
        '/v1/level/move-entity',
        body: {
          'path': 'assets/levels/a.json',
          'name': 'player',
          'x': 7,
          'y': 8,
        },
      );
      expect(w.status, 200, reason: '${w.body}');
      expect(
        File('${project.path}/assets/levels/a.json').readAsStringSync(),
        contains('7'),
      );
      expect(w.body['undoId'], isNotNull);

      await server.close();
      server = await start(readOnly: true);
      final denied = await send(
        'POST',
        '/v1/level/move-entity',
        body: {
          'path': 'assets/levels/a.json',
          'name': 'player',
          'x': 1,
          'y': 1,
        },
      );
      expect(denied.status, ErrorCode.readOnly.http);
    },
  );

  test(
    'catalogue and operation spec over GET, OpenAPI from the registry',
    () async {
      final list = await send(
        'GET',
        '/v1/engine/operations?group=level&kind=read',
      );
      expect(list.status, 200);
      expect((list.body['data'] as List).map((o) => o['group']).toSet(), {
        'level',
      });
      final one = await send('GET', '/v1/engine/operations/level.add_entity');
      expect(one.body['data']['inputSchema'], isNotNull);
      expect((await send('GET', '/v1/engine/operations/no.such')).status, 404);

      final api = await send('GET', '/v1/openapi.json');
      expect(api.body['openapi'], '3.1.0');
      final paths = api.body['paths'] as Map;
      expect(paths, contains('/v1/level/add_entity'));
      expect(paths, isNot(contains('/v1/project/create')));
    },
  );

  test(
    'JSON-RPC: method is the operation, errors carry the engine code',
    () async {
      final ok = await send(
        'POST',
        '/rpc',
        body: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'level.list',
          'params': <String, Object?>{},
        },
      );
      expect(ok.body['result']['data'][0]['path'], 'assets/levels/a.json');
      expect(ok.body['result']['meta']['durationMs'], isA<int>());
      final bad = await send(
        'POST',
        '/rpc',
        body: {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'level.read',
          'params': {'path': 'zzz.json'},
        },
      );
      expect(bad.body['error']['code'], ErrorCode.notFound.rpc);
      expect(bad.body['error']['data']['code'], 'not_found');
      final none = await send(
        'POST',
        '/rpc',
        body: {'jsonrpc': '2.0', 'id': 3, 'method': 'x.y'},
      );
      expect(none.body['error']['code'], -32601);
      final discover = await send(
        'POST',
        '/rpc',
        body: {'jsonrpc': '2.0', 'id': 4, 'method': 'rpc.discover'},
      );
      expect(discover.body['result'], isNotEmpty);
    },
  );

  test('JSON-RPC batches run in order and notifications get 204', () async {
    final r = await send(
      'POST',
      '/rpc',
      body: [
        {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'level.move_entity',
          'params': {
            'path': 'assets/levels/a.json',
            'name': 'player',
            'x': 3,
            'y': 3,
          },
        },
        {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'level.read',
          'params': {'path': 'assets/levels/a.json'},
        },
      ],
    );
    expect((r.body as List).map((x) => x['id']), [1, 2]);
    expect(jsonEncode(r.body[1]['result']['data']), contains('"x":3'));
    expect(
      (await send(
        'POST',
        '/rpc',
        body: {'jsonrpc': '2.0', 'method': 'engine.health'},
      )).status,
      204,
    );
  });

  test(
    'MCP over HTTP: initialize, tools/list, tools/call; notifications get 202',
    () async {
      final init = await send(
        'POST',
        '/mcp',
        body: {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}},
      );
      expect(init.body['result']['protocolVersion'], mcpProtocolVersion);
      final call = await send(
        'POST',
        '/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {'name': 'level.list', 'arguments': <String, Object?>{}},
        },
      );
      expect(call.body['result']['isError'], false);
      expect(
        (await send(
          'POST',
          '/mcp',
          body: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        )).status,
        202,
      );
      expect((await send('GET', '/mcp')).status, 405);
    },
  );

  test('oversized bodies are refused with 413', () async {
    await server.close();
    server = await start(maxBytes: 64);
    final r = await send('POST', '/v1/level/read', body: {'path': 'a' * 200});
    expect(r.status, 413);
  });

  test('DNS rebinding: a foreign Host header is refused', () async {
    final r = await send(
      'POST',
      '/v1/level/list',
      headers: {'host': 'evil.example:80'},
    );
    expect(r.status, 403);
  });

  test('X-Request-Id is echoed or generated', () async {
    expect(
      (await send(
        'GET',
        '/v1/health',
        headers: {'x-request-id': 'abc'},
      )).headers.value('x-request-id'),
      'abc',
    );
    expect(
      (await send('GET', '/v1/health')).headers.value('x-request-id'),
      isNotEmpty,
    );
  });

  test('binding beyond localhost needs --allow-remote', () async {
    expect(
      () => EngineHttpServer.start(
        McpSession(buildRegistry(), OpContext()),
        token: token,
        host: '0.0.0.0',
      ),
      throwsArgumentError,
    );
  });

  test(
    'CORS: only listed origins are answered, preflight needs no token',
    () async {
      await server.close();
      server = await EngineHttpServer.start(
        McpSession(
          buildRegistry(),
          OpContext(project: ProjectRoot(project.path)),
        ),
        token: token,
        allowedOrigins: ['https://studio.example'],
      );
      final ok = await send(
        'POST',
        '/v1/level/list',
        headers: {'origin': 'https://studio.example'},
      );
      expect(
        ok.headers.value('access-control-allow-origin'),
        'https://studio.example',
      );
      final other = await send(
        'POST',
        '/v1/level/list',
        headers: {'origin': 'https://evil.example'},
      );
      expect(other.headers.value('access-control-allow-origin'), isNull);
      final pre = await send(
        'OPTIONS',
        '/v1/level/list',
        auth: null,
        headers: {'origin': 'https://studio.example'},
      );
      expect(pre.status, 204);
      expect(
        pre.headers.value('access-control-allow-headers'),
        contains('authorization'),
      );
    },
  );

  test(
    'Idempotency-Key replays the stored answer and rejects a different body',
    () async {
      final body = {
        'path': 'assets/levels/a.json',
        'name': 'player',
        'x': 4,
        'y': 4,
      };
      final first = await send(
        'POST',
        '/v1/level/move-entity',
        body: body,
        headers: {'idempotency-key': 'k1'},
      );
      final again = await send(
        'POST',
        '/v1/level/move-entity',
        body: body,
        headers: {'idempotency-key': 'k1'},
      );
      expect(first.status, 200);
      expect(
        again.body['undoId'],
        first.body['undoId'],
        reason: 'replayed, not re-run',
      );
      final undo = await send('POST', '/v1/undo/list');
      expect((undo.body['data'] as List), hasLength(1));
      final other = await send(
        'POST',
        '/v1/level/move-entity',
        body: {...body, 'x': 5},
        headers: {'idempotency-key': 'k1'},
      );
      expect(other.status, 409);
      final fresh = await send(
        'POST',
        '/v1/level/move-entity',
        body: {...body, 'x': 5},
        headers: {'idempotency-key': 'k2'},
      );
      expect(fresh.status, 200);
    },
  );

  test('repeated bad tokens are slowed down', () async {
    server.authFailureDelay = const Duration(milliseconds: 300);
    for (var i = 0; i < 5; i++) {
      expect(
        (await send('POST', '/v1/level/list', auth: 'Bearer nope')).status,
        401,
      );
    }
    final sw = Stopwatch()..start();
    expect(
      (await send('POST', '/v1/level/list', auth: 'Bearer nope')).status,
      401,
    );
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(250));
    sw.reset();
    expect(
      (await send('POST', '/v1/level/list')).status,
      200,
      reason: 'a good token is not penalised',
    );
    expect(sw.elapsedMilliseconds, lessThan(250));
  });

  test(
    'an HTTP server started on a project cannot be pointed elsewhere',
    () async {
      final root = ProjectRoot(project.path);
      final http = contextFromArgs(
        buildServerParser().parse(['--http']),
        root,
        (_) {},
      );
      expect(http.allowProjectSwitch, isFalse);
      final stdio = contextFromArgs(
        buildServerParser().parse([]),
        root,
        (_) {},
      );
      expect(
        stdio.allowProjectSwitch,
        isTrue,
        reason: 'a local stdio client may switch',
      );
      final unbound = contextFromArgs(
        buildServerParser().parse(['--http']),
        null,
        (_) {},
      );
      expect(
        unbound.allowProjectSwitch,
        isTrue,
        reason: 'with no project yet there is something to open',
      );
      final r = await buildRegistry().call('project.close', {}, http);
      expect(r.error!.code, ErrorCode.forbidden);
      final restricted = contextFromArgs(
        buildServerParser().parse(['--allow-open', '/only/here/*']),
        null,
        (_) {},
      );
      final denied = await buildRegistry().call('project.open', {
        'path': project.path,
      }, restricted);
      expect(denied.error!.code, ErrorCode.forbidden);
    },
  );

  group('tokens', () {
    test('generated tokens are 43 url-safe characters and unique', () {
      final a = generateToken(), b = generateToken();
      expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(a, isNot(b));
    });

    test('tokensMatch compares whole strings', () {
      expect(tokensMatch('abc', 'abc'), isTrue);
      expect(tokensMatch('abc', 'abd'), isFalse);
      expect(tokensMatch('abc', 'abcd'), isFalse);
    });

    test(
      'resolveToken prefers explicit, then stored, and rotates on request',
      () {
        expect(resolveToken(explicit: 'x', projectRoot: project.path), 'x');
        final first = resolveToken(projectRoot: project.path);
        expect(
          File('${project.path}/.studio/api-token').readAsStringSync(),
          first,
        );
        expect(resolveToken(projectRoot: project.path), first);
        expect(
          resolveToken(projectRoot: project.path, rotate: true),
          isNot(first),
        );
        if (!Platform.isWindows) {
          expect(
            File('${project.path}/.studio/api-token').statSync().mode & 0x1ff,
            384,
          );
        }
      },
    );
  });
}
