import 'dart:convert';
import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:test/test.dart';

late Directory project;

setUp_() {
  project = Directory.systemTemp.createTempSync('mcp_proto');
  File(
    '${project.path}/pubspec.yaml',
  ).writeAsStringSync('name: demo\nversion: 1.0.0\n');
  Directory('${project.path}/assets/levels').createSync(recursive: true);
  File('${project.path}/assets/levels/a.json').writeAsStringSync(
    '{"entities": [{"name": "player", "components": {"position": {"x": 1, "y": 2}}}]}',
  );
}

/// Sends [requests] (one JSON message per line) through the stdio server and returns the replies.
Future<List<Map<String, dynamic>>> talk(
  List<Object?> requests, {
  List<String> flags = const [],
}) async {
  final out = <String>[];
  final input = Stream.value(
    utf8.encode('${requests.map(jsonEncode).join('\n')}\n'),
  );
  final code = await runServer(
    ['--project', project.path, ...flags],
    input: input,
    write: out.add,
    err: (_) {},
  );
  expect(code, 0);
  return [for (final l in out) jsonDecode(l) as Map<String, dynamic>];
}

Map<String, Object?> req(
  int id,
  String method, [
  Map<String, Object?>? params,
]) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': method,
  if (params != null) 'params': params,
};

void main() {
  setUp(setUp_);
  tearDown(() => project.deleteSync(recursive: true));

  test(
    'initialize negotiates our protocol version and describes the server',
    () async {
      final r = (await talk([
        req(1, 'initialize', {'protocolVersion': '1999-01-01'}),
      ])).single;
      expect(r['id'], 1);
      final result = r['result'] as Map;
      expect(result['protocolVersion'], mcpProtocolVersion);
      expect((result['serverInfo'] as Map)['name'], 'engine_api');
      expect(result['capabilities'], contains('tools'));
      expect(result['instructions'], contains('project.open'));
    },
  );

  test(
    'notifications get no reply, ping is answered, unknown methods are -32601',
    () async {
      final replies = await talk([
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        req(2, 'ping'),
        req(3, 'nope/nothing'),
      ]);
      expect(replies.map((r) => r['id']), [2, 3]);
      expect(replies[0]['result'], isEmpty);
      expect((replies[1]['error'] as Map)['code'], -32601);
    },
  );

  test(
    'garbage is a parse error and a bad request an invalid-request error',
    () async {
      final out = <String>[];
      await runServer(
        [],
        input: Stream.value(
          utf8.encode('{nope\n{"jsonrpc":"2.0","id":1}\n[]\n'),
        ),
        write: out.add,
        err: (_) {},
      );
      final codes = [
        for (final l in out) ((jsonDecode(l) as Map)['error'] as Map)['code'],
      ];
      expect(codes, [-32700, -32600, -32600]);
    },
  );

  test(
    'tools/list serves every non-Flutter operation with schema, annotations and a detailed description',
    () async {
      final all = <Map>[];
      String? cursor;
      do {
        final r =
            (await talk([
                  req(1, 'tools/list', {if (cursor != null) 'cursor': cursor}),
                ])).single['result']
                as Map;
        all.addAll((r['tools'] as List).cast<Map>());
        cursor = r['nextCursor'] as String?;
      } while (cursor != null);
      final names = all.map((t) => t['name']).toSet();
      expect(
        names,
        containsAll(['project.open', 'level.add_entity', 'engine.operations']),
      );
      expect(
        names,
        isNot(contains('project.create')),
        reason: 'Flutter-only operations are CLI-only',
      );
      final add = all.firstWhere((t) => t['name'] == 'level.add_entity');
      expect((add['inputSchema'] as Map)['properties'], contains('apply'));
      expect((add['annotations'] as Map)['readOnlyHint'], false);
      expect(add['description'], contains('Kind: write'));
      final remove = all.firstWhere((t) => t['name'] == 'level.remove_entity');
      expect((remove['annotations'] as Map)['destructiveHint'], true);
    },
  );

  test(
    'tools/call runs an operation and returns the envelope as text and structuredContent',
    () async {
      final r =
          (await talk([
                req(1, 'tools/call', {
                  'name': 'level.list',
                  'arguments': <String, Object?>{},
                }),
              ])).single['result']
              as Map;
      expect(r['isError'], false);
      final envelope = r['structuredContent'] as Map;
      expect(envelope['ok'], true);
      expect(
        jsonDecode((r['content'] as List).single['text'] as String),
        envelope,
      );
      expect(
        ((envelope['data'] as List).single as Map)['path'],
        'assets/levels/a.json',
      );
    },
  );

  test(
    'operation failures are isError results, protocol misuse is a JSON-RPC error',
    () async {
      final replies = await talk([
        req(1, 'tools/call', {
          'name': 'level.read',
          'arguments': {'path': 'assets/levels/none.json'},
        }),
        req(2, 'tools/call', {'name': 'no.such'}),
        req(3, 'tools/call', {'arguments': {}}),
      ]);
      final first = replies[0]['result'] as Map;
      expect(first['isError'], true);
      expect(
        ((first['structuredContent'] as Map)['error'] as Map)['code'],
        'not_found',
      );
      expect((replies[1]['error'] as Map)['code'], -32602);
      expect((replies[2]['error'] as Map)['code'], -32602);
    },
  );

  test('a write over MCP changes the file; --read-only refuses it', () async {
    final call = req(1, 'tools/call', {
      'name': 'level.move_entity',
      'arguments': {
        'path': 'assets/levels/a.json',
        'name': 'player',
        'x': 9,
        'y': 9,
      },
    });
    final denied =
        (await talk([call], flags: ['--read-only'])).single['result'] as Map;
    expect(
      ((denied['structuredContent'] as Map)['error'] as Map)['code'],
      'read_only',
    );
    final ok = (await talk([call])).single['result'] as Map;
    expect(ok['isError'], false, reason: '${ok['structuredContent']}');
    expect(
      File('${project.path}/assets/levels/a.json').readAsStringSync(),
      contains('9'),
    );
  });

  test(
    '--allow and --deny filter the tool list and the callable operations',
    () async {
      final r =
          (await talk(
                [req(1, 'tools/list')],
                flags: ['--allow', 'engine.*'],
              )).single['result']
              as Map;
      expect([
        for (final t in r['tools'] as List) (t as Map)['name'],
      ], everyElement(startsWith('engine.')));
      final blocked = (await talk(
        [
          req(1, 'tools/call', {'name': 'engine.health'}),
        ],
        flags: ['--deny', 'engine.health'],
      )).single;
      expect(
        blocked['error'],
        isNotNull,
        reason: 'a hidden tool is unknown, not callable',
      );
    },
  );

  test('--underscore-tool-names renames tools on the wire only', () async {
    final r =
        (await talk(
              [
                req(1, 'tools/call', {'name': 'engine_health'}),
              ],
              flags: ['--underscore-tool-names'],
            )).single['result']
            as Map;
    expect(r['isError'], false);
    final list =
        (await talk(
              [req(1, 'tools/list')],
              flags: ['--underscore-tool-names'],
            )).single['result']
            as Map;
    expect([
      for (final t in list['tools'] as List) (t as Map)['name'],
    ], everyElement(isNot(contains('.'))));
  });

  test('resources: catalogue, operation spec and component schema', () async {
    final replies = await talk([
      req(1, 'resources/list'),
      req(2, 'resources/templates/list'),
      req(3, 'resources/read', {'uri': 'engine://operations/level.add_entity'}),
      req(4, 'resources/read', {'uri': 'engine://schemas/components/position'}),
      req(5, 'resources/read', {'uri': 'engine://nope'}),
    ]);
    expect((replies[0]['result'] as Map)['resources'], isNotEmpty);
    expect((replies[1]['result'] as Map)['resourceTemplates'], hasLength(2));
    final spec =
        jsonDecode(
              ((replies[2]['result'] as Map)['contents'] as List).single['text']
                  as String,
            )
            as Map;
    expect(spec['name'], 'level.add_entity');
    expect(spec['inputSchema'], isNotNull);
    expect(((replies[3]['result'] as Map)['contents'] as List), hasLength(1));
    expect((replies[4]['error'] as Map)['code'], -32002);
  });

  test('a batch gets one array reply', () async {
    final out = <String>[];
    await runServer(
      [],
      input: Stream.value(
        utf8.encode('${jsonEncode([req(1, 'ping'), req(2, 'ping')])}\n'),
      ),
      write: out.add,
      err: (_) {},
    );
    expect(jsonDecode(out.single), hasLength(2));
  });
}
