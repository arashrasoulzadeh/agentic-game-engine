import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('a well-formed linear graph has no issues', () {
    const graph = Graph(
      nodes: [
        GraphNode(id: 'a', kind: 'say'),
        GraphNode(id: 'b', kind: 'say'),
      ],
      edges: [
        GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 'b', toPort: 'in'),
      ],
      entryNodeId: 'a',
    );
    expect(validateGraph(graph), isEmpty);
  });

  test('an unknown node kind is reported', () {
    const graph = Graph(
      nodes: [GraphNode(id: 'a', kind: 'doesNotExist')],
      entryNodeId: 'a',
    );
    final issues = validateGraph(graph);
    expect(issues.single.kind, GraphIssueKind.unknownNodeKind);
    expect(issues.single.nodeId, 'a');
  });

  group('missing entry', () {
    test('no entryNodeId at all', () {
      const graph = Graph(
        nodes: [GraphNode(id: 'a', kind: 'say')],
      );
      expect(
        validateGraph(graph).map((i) => i.kind),
        contains(GraphIssueKind.missingEntry),
      );
    });

    test('an entryNodeId naming a node that does not exist', () {
      const graph = Graph(
        nodes: [GraphNode(id: 'a', kind: 'say')],
        entryNodeId: 'nope',
      );
      expect(
        validateGraph(graph).map((i) => i.kind),
        contains(GraphIssueKind.missingEntry),
      );
    });
  });

  group('port checks', () {
    test('an edge naming a port its node does not have is reported', () {
      const graph = Graph(
        nodes: [
          GraphNode(id: 'a', kind: 'say'),
          GraphNode(id: 'b', kind: 'say'),
        ],
        edges: [
          GraphEdge(
            fromNode: 'a',
            fromPort: 'notAPort',
            toNode: 'b',
            toPort: 'in',
          ),
        ],
        entryNodeId: 'a',
      );
      expect(
        validateGraph(graph).map((i) => i.kind),
        contains(GraphIssueKind.unknownPort),
      );
    });

    test('connecting a flow output to a non-flow input is a type mismatch', () {
      const graph = Graph(
        nodes: [
          GraphNode(id: 'a', kind: 'say'),
          GraphNode(id: 'b', kind: 'branch'),
        ],
        edges: [
          // 'out' on say is flow; 'condition' on branch is boolean.
          GraphEdge(
            fromNode: 'a',
            fromPort: 'out',
            toNode: 'b',
            toPort: 'condition',
          ),
        ],
        entryNodeId: 'a',
      );
      expect(
        validateGraph(graph).map((i) => i.kind),
        contains(GraphIssueKind.portTypeMismatch),
      );
    });

    test('a choice node\'s per-choice output ports type-check as flow', () {
      const graph = Graph(
        nodes: [
          GraphNode(
            id: 'a',
            kind: 'choice',
            params: {
              'choices': [
                {'id': 'yes', 'textKey': 'Yes'},
              ],
            },
          ),
          GraphNode(id: 'b', kind: 'say'),
        ],
        edges: [
          GraphEdge(fromNode: 'a', fromPort: 'yes', toNode: 'b', toPort: 'in'),
        ],
        entryNodeId: 'a',
      );
      expect(validateGraph(graph), isEmpty);
    });
  });

  test('a node no edge from the entry reaches is unreachable', () {
    const graph = Graph(
      nodes: [
        GraphNode(id: 'a', kind: 'say'),
        GraphNode(id: 'orphan', kind: 'say'),
      ],
      entryNodeId: 'a',
    );
    final issues = validateGraph(graph);
    expect(issues.single.kind, GraphIssueKind.unreachableNode);
    expect(issues.single.nodeId, 'orphan');
  });

  group('cycles', () {
    test('a cycle with a wait node in it is not reported', () {
      const graph = Graph(
        nodes: [
          GraphNode(id: 'a', kind: 'say'),
          GraphNode(id: 'w', kind: 'wait'),
        ],
        edges: [
          GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 'w', toPort: 'in'),
          GraphEdge(fromNode: 'w', fromPort: 'out', toNode: 'a', toPort: 'in'),
        ],
        entryNodeId: 'a',
      );
      expect(
        validateGraph(
          graph,
        ).where((i) => i.kind == GraphIssueKind.cycleWithoutWait),
        isEmpty,
      );
    });

    test('a cycle with no wait node is reported', () {
      const graph = Graph(
        nodes: [
          GraphNode(id: 'a', kind: 'say'),
          GraphNode(id: 'b', kind: 'say'),
        ],
        edges: [
          GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 'b', toPort: 'in'),
          GraphEdge(fromNode: 'b', fromPort: 'out', toNode: 'a', toPort: 'in'),
        ],
        entryNodeId: 'a',
      );
      final issues = validateGraph(graph);
      expect(
        issues.map((i) => i.kind),
        contains(GraphIssueKind.cycleWithoutWait),
      );
    });

    test('a self-loop with no wait node is reported', () {
      const graph = Graph(
        nodes: [GraphNode(id: 'a', kind: 'say')],
        edges: [
          GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 'a', toPort: 'in'),
        ],
        entryNodeId: 'a',
      );
      expect(
        validateGraph(graph).map((i) => i.kind),
        contains(GraphIssueKind.cycleWithoutWait),
      );
    });

    test('no cycle at all means nothing is reported for it', () {
      const graph = Graph(
        nodes: [
          GraphNode(id: 'a', kind: 'say'),
          GraphNode(id: 'b', kind: 'say'),
          GraphNode(id: 'c', kind: 'say'),
        ],
        edges: [
          GraphEdge(fromNode: 'a', fromPort: 'out', toNode: 'b', toPort: 'in'),
          GraphEdge(fromNode: 'b', fromPort: 'out', toNode: 'c', toPort: 'in'),
        ],
        entryNodeId: 'a',
      );
      expect(
        validateGraph(
          graph,
        ).where((i) => i.kind == GraphIssueKind.cycleWithoutWait),
        isEmpty,
      );
    });
  });
}
