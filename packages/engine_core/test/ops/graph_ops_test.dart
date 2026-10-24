import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

const g = 'graphs/talk.json';

Map<String, dynamic> file(Scratch s, String p) =>
    jsonDecode(s.read(p)) as Map<String, dynamic>;

void main() {
  test('create, add nodes, connect, validate a dialogue graph', () async {
    final s = await Scratch.create();
    await s.data('graph.create', {'path': g});
    expect(file(s, g)['graph'], {'nodes': [], 'edges': []});
    final a = await s.map('graph.add_node', {
      'path': g,
      'kind': 'say',
      'params': {'textKey': 'hi'},
    });
    expect((a['node']! as Map)['id'], 'say0');
    await s.data('graph.add_node', {'path': g, 'kind': 'say'});
    expect(
      file(s, g)['graph']['entryNodeId'],
      'say0',
      reason: 'first node is the entry',
    );
    final e = await s.map('graph.connect', {
      'path': g,
      'from': 'say0',
      'fromPort': 'out',
      'to': 'say1',
      'toPort': 'in',
    });
    expect(e['edge'], containsPair('toNode', 'say1'));
    expect((await s.map('graph.validate', {'path': g}))['ok'], isTrue);
    final list = await s.data('graph.list') as List;
    expect(list.map((x) => (x as Map)['nodes']), contains(2));
  });

  test(
    'connect checks ports and types, duplicates and unknown nodes',
    () async {
      final s = await Scratch.create();
      await s.data('graph.create', {'path': g});
      await s.data('graph.add_node', {'path': g, 'kind': 'say'});
      await s.data('graph.add_node', {'path': g, 'kind': 'branch'});
      final connect = {
        'path': g,
        'from': 'say0',
        'fromPort': 'out',
        'to': 'branch1',
        'toPort': 'in',
      };
      await s.data('graph.connect', connect);
      expect(await s.failure('graph.connect', connect), ErrorCode.conflict);
      expect(
        await s.failure('graph.connect', {...connect, 'toPort': 'condition'}),
        ErrorCode.validationFailed,
        reason: 'flow output into a boolean input',
      );
      expect(
        await s.failure('graph.connect', {...connect, 'fromPort': 'nope'}),
        ErrorCode.invalidParams,
      );
      expect(
        await s.failure('graph.connect', {...connect, 'to': 'ghost'}),
        ErrorCode.notFound,
      );
      await s.data('graph.disconnect', connect);
      expect(await s.failure('graph.disconnect', connect), ErrorCode.notFound);
    },
  );

  test(
    'add_node refuses unknown kinds and duplicate ids; set_param reports before/after',
    () async {
      final s = await Scratch.create();
      await s.data('graph.create', {'path': g});
      expect(
        await s.failure('graph.add_node', {'path': g, 'kind': 'nope'}),
        ErrorCode.invalidParams,
      );
      await s.data('graph.add_node', {'path': g, 'kind': 'say', 'id': 'n'});
      expect(
        await s.failure('graph.add_node', {
          'path': g,
          'kind': 'say',
          'id': 'n',
        }),
        ErrorCode.conflict,
      );
      await s.data('graph.set_param', {
        'path': g,
        'node': 'n',
        'param': 'textKey',
        'value': 'a',
      });
      final r = await s.map('graph.set_param', {
        'path': g,
        'node': 'n',
        'param': 'textKey',
        'value': 'b',
      });
      expect(r, {'before': 'a', 'after': 'b'});
      expect(
        await s.failure('graph.set_param', {
          'path': g,
          'node': 'zz',
          'param': 'x',
          'value': 1,
        }),
        ErrorCode.notFound,
      );
    },
  );

  test(
    'remove_node is destructive, drops its edges and the entry, and undoes',
    () async {
      final s = await Scratch.create();
      await s.data('graph.create', {'path': g});
      await s.data('graph.add_node', {'path': g, 'kind': 'say'});
      await s.data('graph.add_node', {'path': g, 'kind': 'say'});
      await s.data('graph.connect', {
        'path': g,
        'from': 'say0',
        'fromPort': 'out',
        'to': 'say1',
        'toPort': 'in',
      });
      final before = s.read(g);
      final preview = await s.map('graph.remove_node', {
        'path': g,
        'id': 'say0',
      });
      expect(s.read(g), before);
      await s.data('graph.remove_node', {
        'path': g,
        'id': 'say0',
        'confirmation': preview['confirmation'],
      });
      final after = file(s, g)['graph'] as Map;
      expect(after['edges'], isEmpty);
      expect(after.containsKey('entryNodeId'), isFalse);
      await s.data('undo.undo');
      expect(s.read(g), before);
    },
  );

  test(
    'behavior trees: kind defaults, validate and compile (ordered by canvas x)',
    () async {
      final s = await Scratch.create();
      await s.data('graph.create', {
        'path': 'graphs/bt.json',
        'type': 'behaviorTree',
      });
      const p = 'graphs/bt.json';
      await s.data('graph.add_node', {
        'path': p,
        'kind': 'sequence',
        'id': 'root',
      });
      await s.data('graph.add_node', {
        'path': p,
        'kind': 'wait',
        'id': 'w',
        'x': 20,
      });
      await s.data('graph.add_node', {
        'path': p,
        'kind': 'wait',
        'id': 'early',
        'x': 10,
      });
      expect(file(s, p)['graph']['nodes'][1]['params'], {'duration': 1.0});
      for (final c in ['w', 'early']) {
        await s.data('graph.connect', {
          'path': p,
          'from': 'root',
          'fromPort': 'children',
          'to': c,
          'toPort': 'in',
        });
      }
      expect((await s.map('graph.validate', {'path': p}))['ok'], isTrue);
      final compiled =
          (await s.map('graph.compile', {'path': p}))['compiled']! as Map;
      expect(compiled['type'], 'sequence');
      expect(
        [for (final c in compiled['children'] as List) (c as Map)['id']],
        ['early', 'w'],
        reason: 'children follow the canvas, left to right',
      );
      await s.data('graph.compile', {'path': p, 'output': 'assets/bt.json'});
      expect(s.exists('assets/bt.json'), isTrue);
    },
  );

  test(
    'compile reports the node a bad tree stops at; dialogue has no compiled form',
    () async {
      final s = await Scratch.create();
      await s.data('graph.create', {
        'path': 'graphs/bt2.json',
        'type': 'behaviorTree',
      });
      await s.data('graph.add_node', {
        'path': 'graphs/bt2.json',
        'kind': 'inverter',
        'id': 'root',
      });
      expect(
        await s.failure('graph.compile', {'path': 'graphs/bt2.json'}),
        ErrorCode.validationFailed,
      );
      await s.data('graph.create', {'path': g});
      expect((await s.map('graph.compile', {'path': g}))['compiled'], isNull);
    },
  );

  test('node_kinds, bad paths and bad files', () async {
    final s = await Scratch.create(open: true);
    final kinds =
        await s.data('graph.node_kinds', {'type': 'behaviorTree'}) as List;
    expect(
      kinds.map((k) => (k as Map)['name']),
      containsAll(['sequence', 'wait']),
    );
    expect(
      await s.failure('graph.create', {'path': 'elsewhere/x.json'}),
      ErrorCode.invalidParams,
    );
    expect(
      await s.failure('graph.create', {'path': 'graphs/graph1.json'}),
      ErrorCode.conflict,
    );
    expect(
      await s.failure('graph.read', {'path': 'graphs/none.json'}),
      ErrorCode.notFound,
    );
    s.write('graphs/bad.json', '{"graph": 5}');
    expect(
      await s.failure('graph.read', {'path': 'graphs/bad.json'}),
      ErrorCode.validationFailed,
    );
  });
}
