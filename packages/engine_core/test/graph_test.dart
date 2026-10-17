import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('Graph JSON round-trip', () {
    test('every field survives toJson/fromJson', () {
      const graph = Graph(
        nodes: [
          GraphNode(id: 'a', kind: 'say', params: {'textKey': 'hi'}),
          GraphNode(id: 'b', kind: 'say'),
        ],
        edges: [
          GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 'b', toPort: 'in'),
        ],
        variables: [
          GraphVariable(name: 'met', type: PortType.boolean, initialValue: false),
        ],
        entryNodeId: 'a',
      );
      final decoded = Graph.fromJson(graph.toJson());

      expect(decoded.nodes.map((n) => n.id), ['a', 'b']);
      expect(decoded.nodes.first.params['textKey'], 'hi');
      expect(decoded.edges.single.fromNode, 'a');
      expect(decoded.edges.single.toPort, 'in');
      expect(decoded.variables.single.name, 'met');
      expect(decoded.variables.single.type, PortType.boolean);
      expect(decoded.variables.single.initialValue, false);
      expect(decoded.entryNodeId, 'a');
    });

    test('an empty graph round-trips to an empty graph', () {
      const graph = Graph();
      final decoded = Graph.fromJson(graph.toJson());
      expect(decoded.nodes, isEmpty);
      expect(decoded.edges, isEmpty);
      expect(decoded.variables, isEmpty);
      expect(decoded.entryNodeId, isNull);
    });
  });

  group('Graph lookups', () {
    const graph = Graph(
      nodes: [
        GraphNode(id: 'a', kind: 'say'),
        GraphNode(id: 'b', kind: 'say'),
      ],
      edges: [
        GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 'b', toPort: 'in'),
      ],
    );

    test('nodeById finds an existing node, or null for a missing one', () {
      expect(graph.nodeById('a')!.kind, 'say');
      expect(graph.nodeById('nope'), isNull);
    });

    test('outgoingFrom lists every edge leaving a node', () {
      expect(graph.outgoingFrom('a'), hasLength(1));
      expect(graph.outgoingFrom('b'), isEmpty);
    });

    test('outgoingPort finds the edge on a specific port, or null', () {
      expect(graph.outgoingPort('a', 'out')!.toNode, 'b');
      expect(graph.outgoingPort('a', 'somethingElse'), isNull);
    });
  });

  group('builtinNodeKinds', () {
    test('has exactly the kinds docs/studio/design.md 4.4 lists', () {
      expect(
        builtinNodeKinds.keys,
        containsAll([
          'say',
          'choice',
          'setVar',
          'getVar',
          'branch',
          'wait',
          'playCinematic',
          'emitEvent',
          'spawnEntity',
        ]),
      );
    });

    test('branch has a condition input and two flow outputs', () {
      final branch = builtinNodeKinds['branch']!;
      expect(branch.inputNamed('condition')!.type, PortType.boolean);
      expect(branch.outputNamed('true')!.type, PortType.flow);
      expect(branch.outputNamed('false')!.type, PortType.flow);
    });

    test('a port not on the kind is not found', () {
      expect(builtinNodeKinds['say']!.outputNamed('nope'), isNull);
    });

    test('say requires a textKey param', () {
      final textKey = builtinNodeKinds['say']!.paramsSchema
          .firstWhere((f) => f.name == 'textKey');
      expect(textKey.type, FieldType.string);
      expect(textKey.required, isTrue);
    });

    test('branch has no params of its own, only ports', () {
      expect(builtinNodeKinds['branch']!.paramsSchema, isEmpty);
    });
  });
}
