import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

GraphNode _n(String id, String kind, [Map<String, dynamic> params = const {}]) =>
    GraphNode(id: id, kind: kind, params: params);

GraphEdge _e(String from, String port, String to) =>
    GraphEdge(fromNode: from, fromPort: port, toNode: to, toPort: 'in');

void main() {
  group('kinds', () {
    test('every node type the engine can load has a kind, and nothing else', () {
      // The engine's BTNode.fromJson switch, by round-tripping one of each.
      final engineTypes = {
        'sequence', 'selector', 'parallel', 'inverter', 'repeater', 'succeeder', 'failer', 'leaf',
        'wait', 'cooldown', 'randomSelector', 'randomSequence', 'untilSuccess', 'untilFailure',
        'timeout', 'throttle', 'timer',
      };
      expect(behaviorTreeNodeKinds.keys.toSet(), engineTypes);
    });

    test('composites have a children port, decorators a child port, leaves neither', () {
      for (final k in behaviorTreeNodeKinds.values) {
        final composite = k.outputNamed('children') != null;
        final decorator = k.outputNamed('child') != null;
        expect(composite && decorator, isFalse, reason: k.name);
        expect(k.inputNamed('in'), isNotNull, reason: k.name);
      }
      expect(behaviorTreeNodeKinds['sequence']!.outputNamed('children'), isNotNull);
      expect(behaviorTreeNodeKinds['inverter']!.outputNamed('child'), isNotNull);
      expect(behaviorTreeNodeKinds['wait']!.outputs, isEmpty);
    });

    test('GraphType picks the registry and parses leniently', () {
      expect(GraphType.dialogue.registry, same(builtinNodeKinds));
      expect(GraphType.behaviorTree.registry, same(behaviorTreeNodeKinds));
      expect(GraphType.stateMachine.registry, same(stateMachineNodeKinds));
      expect(GraphType.parse('behaviorTree'), GraphType.behaviorTree);
      expect(GraphType.parse(null), GraphType.dialogue);
      expect(GraphType.parse('nonsense'), GraphType.dialogue);
    });
  });

  group('compileBehaviorTree', () {
    Graph patrol() => Graph(
          entryNodeId: 'root',
          nodes: [
            _n('root', 'selector'),
            _n('chase', 'sequence'),
            _n('see', 'leaf', {'behaviorId': 'canSeePlayer'}),
            _n('go', 'leaf', {'behaviorId': 'chase'}),
            _n('flip', 'inverter'),
            _n('rest', 'wait', {'duration': 2.5}),
            _n('again', 'repeater', {'count': 3}),
            _n('walk', 'leaf', {'behaviorId': 'patrol'}),
          ],
          edges: [
            _e('root', 'children', 'chase'),
            _e('root', 'children', 'again'),
            _e('chase', 'children', 'see'),
            _e('chase', 'children', 'go'),
            _e('again', 'child', 'walk'),
          ],
        );

    test('produces the engine\'s JSON, which the engine itself can load and tick', () {
      final json = compileBehaviorTree(patrol());
      expect(json['type'], 'selector');
      final back = BTNode.fromJson(json);
      expect(back, isA<BTSelector>());
      expect(jsonEncode(back.toJson()), jsonEncode(json), reason: 'the engine reads and writes it unchanged');
    });

    test('children come out in the order given by the sort key, not edge order', () {
      final g = Graph(
        entryNodeId: 'r',
        nodes: [_n('r', 'sequence'), _n('a', 'leaf', {'behaviorId': 'a'}), _n('b', 'leaf', {'behaviorId': 'b'})],
        edges: [_e('r', 'children', 'a'), _e('r', 'children', 'b')],
      );
      List<String> ids(Map<String, double> order) =>
          [for (final c in compileBehaviorTree(g, order: order)['children'] as List) c['id'] as String];
      expect(ids(const {}), ['a', 'b'], reason: 'no keys: edge order');
      expect(ids({'a': 300, 'b': 100}), ['b', 'a'], reason: 'b is further left');
      expect(ids({'a': 5, 'b': 5}), ['a', 'b'], reason: 'equal keys: stable');
    });

    test('parameters default from the schema and are copied through', () {
      final g = Graph(
        entryNodeId: 'p',
        nodes: [_n('p', 'parallel'), _n('w', 'wait'), _n('t', 'timer', {'duration': 4.0, 'repeat': true})],
        edges: [_e('p', 'children', 'w'), _e('p', 'children', 't')],
      );
      final json = compileBehaviorTree(g);
      expect(json['requiredSuccess'], 1);
      final kids = json['children'] as List;
      expect(kids[0]['duration'], 1.0);
      expect(kids[1], containsPair('repeat', true));
      expect(BTNode.fromJson(json), isA<BTParallel>());
    });

    test('every kind survives a graph -> JSON -> engine -> JSON round trip', () {
      for (final name in behaviorTreeNodeKinds.keys) {
        final kind = behaviorTreeNodeKinds[name]!;
        final params = {
          for (final f in kind.paramsSchema)
            if (f.defaultValue != null) f.name: f.defaultValue else f.name: 'x',
        };
        final leaf = _n('leaf1', 'leaf', {'behaviorId': 'act'});
        final nodes = [_n('n', name, params)];
        final edges = <GraphEdge>[];
        if (kind.outputNamed('children') != null) {
          nodes.add(leaf);
          edges.add(_e('n', 'children', 'leaf1'));
        } else if (kind.outputNamed('child') != null) {
          nodes.add(leaf);
          edges.add(_e('n', 'child', 'leaf1'));
        }
        final json = compileBehaviorTree(Graph(entryNodeId: 'n', nodes: nodes, edges: edges));
        expect(jsonEncode(BTNode.fromJson(json).toJson()), jsonEncode(json), reason: name);
      }
    });

    test('unreachable nodes are left out rather than failing the compile', () {
      final g = Graph(
        entryNodeId: 'r',
        nodes: [_n('r', 'wait'), _n('orphan', 'wait')],
      );
      expect(compileBehaviorTree(g)['id'], 'r');
    });

    test('even a broken orphan (a decorator with no child yet) does not block the export', () {
      final g = Graph(
        entryNodeId: 'r',
        nodes: [_n('r', 'wait'), _n('half', 'inverter'), _n('empty', 'sequence')],
      );
      expect(compileBehaviorTree(g)['id'], 'r');
      expect(validateBehaviorTree(g), isNotEmpty, reason: 'the editor still reports them');
    });

    test('but a broken node under the root does block it', () {
      final g = Graph(
        entryNodeId: 'r',
        nodes: [_n('r', 'sequence'), _n('half', 'inverter')],
        edges: [_e('r', 'children', 'half')],
      );
      expect(() => compileBehaviorTree(g), throwsA(isA<GraphCompileException>()));
    });
  });

  group('validateBehaviorTree', () {
    List<String> messages(Graph g) => [for (final i in validateBehaviorTree(g)) i.message];

    test('a clean tree has no issues', () {
      final g = Graph(
        entryNodeId: 'r',
        nodes: [_n('r', 'sequence'), _n('a', 'wait')],
        edges: [_e('r', 'children', 'a')],
      );
      expect(validateBehaviorTree(g), isEmpty);
    });

    test('no root, an unknown kind, a childless composite, a leaf with children', () {
      expect(messages(const Graph(nodes: [GraphNode(id: 'a', kind: 'wait')])), contains('the tree has no root node'));
      expect(
        messages(Graph(entryNodeId: 'a', nodes: [_n('a', 'banana')])).single,
        contains('unknown kind "banana"'),
      );
      expect(messages(Graph(entryNodeId: 'a', nodes: [_n('a', 'sequence')])).single, contains('has no children'));
      final leafParent = Graph(
        entryNodeId: 'a',
        nodes: [_n('a', 'wait'), _n('b', 'wait')],
        edges: [GraphEdge(fromNode: 'a', fromPort: 'x', toNode: 'b', toPort: 'in')],
      );
      expect(messages(leafParent).single, contains('is a leaf'));
    });

    test('a decorator needs exactly one child', () {
      final none = Graph(entryNodeId: 'a', nodes: [_n('a', 'inverter')]);
      expect(messages(none).single, contains('needs exactly one child, has 0'));
      final two = Graph(
        entryNodeId: 'a',
        nodes: [_n('a', 'inverter'), _n('b', 'wait'), _n('c', 'wait')],
        edges: [_e('a', 'child', 'b'), _e('a', 'child', 'c')],
      );
      expect(messages(two).single, contains('has 2'));
    });

    test('two parents, a loop and an orphan are all reported', () {
      final shared = Graph(
        entryNodeId: 'r',
        nodes: [_n('r', 'sequence'), _n('s', 'sequence'), _n('x', 'wait')],
        edges: [_e('r', 'children', 's'), _e('r', 'children', 'x'), _e('s', 'children', 'x')],
      );
      expect(messages(shared).any((m) => m.contains('2 parents')), isTrue);

      final loop = Graph(
        entryNodeId: 'r',
        nodes: [_n('r', 'sequence'), _n('s', 'sequence')],
        edges: [_e('r', 'children', 's'), _e('s', 'children', 'r')],
      );
      expect(messages(loop).any((m) => m.contains('loops back')), isTrue);

      final orphan = Graph(entryNodeId: 'r', nodes: [_n('r', 'wait'), _n('o', 'wait')]);
      expect(messages(orphan).single, contains('not connected to the root'));
      expect(validateBehaviorTree(orphan).single.kind, GraphIssueKind.unreachableNode);
    });

    test('compile refuses a broken tree with a message naming the node', () {
      final g = Graph(entryNodeId: 'dec', nodes: [_n('dec', 'inverter')]);
      expect(
        () => compileBehaviorTree(g),
        throwsA(isA<GraphCompileException>().having((e) => e.nodeId, 'nodeId', 'dec')),
      );
      expect(const GraphCompileException('x').toString(), contains('x'));
    });
  });

  group('graphFromBehaviorTree (import)', () {
    Map<String, dynamic> sample() => BTSelector(id: 'root', children: [
          BTSequence(id: 'attack', children: [
            BTLeaf(id: 'see', behaviorId: 'canSee'),
            BTInverter(id: 'not', child: BTWait(id: 'pause', duration: 1.5)),
          ]),
          BTRepeater(id: 'loop', count: 2, child: BTLeaf(id: 'patrol', behaviorId: 'patrol')),
        ]).toJson();

    test('imports the engine\'s JSON and compiling it again gives the same JSON', () {
      final json = sample();
      final imported = graphFromBehaviorTree(json);
      final order = {for (final e in imported.layout.entries) e.key: e.value.$1};
      final back = compileBehaviorTree(imported.graph, order: order);
      expect(jsonEncode(back), jsonEncode(json));
      expect(validateBehaviorTree(imported.graph), isEmpty);
      expect(imported.graph.entryNodeId, 'root');
    });

    test('lays out depth down the page and siblings left to right, parents centred', () {
      final imported = graphFromBehaviorTree(sample(), columnWidth: 100, rowHeight: 50);
      final l = imported.layout;
      expect(l['root']!.$2, 0);
      expect(l['attack']!.$2, 50);
      expect(l['see']!.$2, 100);
      expect(l['see']!.$1, lessThan(l['pause']!.$1), reason: 'siblings in order');
      expect(l['attack']!.$1, lessThan(l['loop']!.$1));
      final xs = [l['attack']!.$1, l['loop']!.$1];
      expect(l['root']!.$1, (xs.first + xs.last) / 2, reason: 'a parent sits above its children');
    });

    test('missing and duplicate ids are made unique; unknown types and untyped nodes are rejected', () {
      final imported = graphFromBehaviorTree({
        'type': 'sequence',
        'children': [
          {'type': 'wait', 'duration': 1.0},
          {'type': 'wait', 'duration': 2.0},
          {'type': 'wait', 'id': 'wait', 'duration': 3.0},
        ],
      });
      final ids = [for (final n in imported.graph.nodes) n.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.first, 'sequence');
      expect(() => graphFromBehaviorTree({'type': 'banana'}), throwsFormatException);
      expect(() => graphFromBehaviorTree({'id': 'x'}), throwsFormatException);
    });

    test('a single leaf is a valid tree', () {
      final imported = graphFromBehaviorTree({'type': 'leaf', 'behaviorId': 'idle', 'id': 'only'});
      expect(compileBehaviorTree(imported.graph)['behaviorId'], 'idle');
    });
  });

  group('compileStateMachine', () {
    Graph machine() => Graph(
          entryNodeId: 'idle',
          nodes: [
            _n('idle', 'state', {'name': 'idle'}),
            _n('chase', 'state', {'name': 'chase', 'behaviorTreeGraph': 'graphs/chase.json'}),
            _n('see', 'transition', {'condition': 'seesPlayer'}),
            _n('lose', 'transition', {'condition': 'lostPlayer'}),
          ],
          edges: [
            GraphEdge(fromNode: 'idle', fromPort: 'out', toNode: 'see', toPort: 'in'),
            GraphEdge(fromNode: 'see', fromPort: 'out', toNode: 'chase', toPort: 'in'),
            GraphEdge(fromNode: 'chase', fromPort: 'out', toNode: 'lose', toPort: 'in'),
            GraphEdge(fromNode: 'lose', fromPort: 'out', toNode: 'idle', toPort: 'in'),
          ],
        );

    test('produces JSON the engine loads into a working StateMachine', () {
      final json = compileStateMachine(machine(),
          id: 'guard',
          resolveTree: (path) => path == 'graphs/chase.json' ? BTWait(id: 'w', duration: 1).toJson() : null);
      expect(json['id'], 'guard');
      expect(json['currentState'], 'idle');

      final fsm = StateMachine.fromJson(json, BehaviorRegistry());
      expect(fsm.currentStateName, 'idle');
      expect(fsm.states.keys, containsAll(['idle', 'chase']));
      expect(fsm.states['idle']!.transitions.keys, ['chase']);
      expect(fsm.states['chase']!.transitions.keys, ['idle']);
      expect(fsm.states['chase']!.behaviorTree, isA<BTWait>());
      expect(fsm.states['idle']!.behaviorTree, isNull);
    });

    test('the transition condition is carried as a name for the game to bind', () {
      final json = compileStateMachine(machine());
      expect(json['states']['idle']['transitions']['chase'],
          {'toState': 'chase', 'condition': 'seesPlayer'});
    });

    test('the entry node picks the initial state; otherwise the first state', () {
      final g = machine();
      final started = Graph(
        nodes: g.nodes,
        edges: g.edges,
        entryNodeId: 'chase',
      );
      expect(compileStateMachine(started)['currentState'], 'chase');
      expect(compileStateMachine(Graph(nodes: g.nodes, edges: g.edges))['currentState'], 'idle');
    });

    test('a state with a tree path but no resolver keeps behaviorTree null', () {
      expect(compileStateMachine(machine())['states']['chase']['behaviorTree'], isNull);
    });

    test('structural mistakes name the offender', () {
      GraphCompileException fail(Graph g) {
        try {
          compileStateMachine(g);
        } on GraphCompileException catch (e) {
          return e;
        }
        throw StateError('expected a failure');
      }

      expect(fail(const Graph()).message, contains('at least one state'));
      expect(fail(Graph(nodes: [_n('a', 'state', {'name': ' '})])).nodeId, 'a');
      expect(
        fail(Graph(nodes: [_n('a', 'state', {'name': 'x'}), _n('b', 'state', {'name': 'x'})])).message,
        contains('two states are named "x"'),
      );

      final direct = Graph(
        nodes: [_n('a', 'state', {'name': 'a'}), _n('b', 'state', {'name': 'b'})],
        edges: [GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 'b', toPort: 'in')],
      );
      expect(fail(direct).message, contains('go through a transition node'));

      final dangling = Graph(
        nodes: [_n('a', 'state', {'name': 'a'}), _n('t', 'transition', {'condition': 'c'})],
        edges: [GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 't', toPort: 'in')],
      );
      expect(fail(dangling).message, contains('exactly one state'));

      final twice = Graph(
        nodes: [
          _n('a', 'state', {'name': 'a'}),
          _n('b', 'state', {'name': 'b'}),
          _n('t1', 'transition', {'condition': 'c1'}),
          _n('t2', 'transition', {'condition': 'c2'}),
        ],
        edges: [
          GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 't1', toPort: 'in'),
          GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 't2', toPort: 'in'),
          GraphEdge(fromNode: 't1', fromPort: 'out', toNode: 'b', toPort: 'in'),
          GraphEdge(fromNode: 't2', fromPort: 'out', toNode: 'b', toPort: 'in'),
        ],
      );
      expect(fail(twice).message, contains('two transitions to "b"'));
    });
  });
}
