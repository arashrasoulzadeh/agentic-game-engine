import 'graph.dart';
import 'node_kind.dart';

/// Every problem [validateGraph] checks for, so a caller can act on which
/// rule fired rather than just a message string.
enum GraphIssueKind {
  unknownNodeKind,
  unknownPort,
  portTypeMismatch,
  missingEntry,
  unreachableNode,
  cycleWithoutWait,
}

class GraphIssue {
  final GraphIssueKind kind;
  final String message;
  final String? nodeId;

  const GraphIssue(this.kind, this.message, {this.nodeId});

  @override
  String toString() => message;
}

/// Checks [graph] against [registry] (every built-in kind by default):
/// unknown node kinds, edges whose port types don't match, a missing or
/// dangling entry node, nodes no edge from the entry ever reaches, and a
/// control-flow cycle with no `wait` node in it (which would otherwise spin
/// forever the instant a compiled version of it ran).
List<GraphIssue> validateGraph(
  Graph graph, {
  Map<String, NodeKind> registry = builtinNodeKinds,
}) {
  final issues = <GraphIssue>[];

  for (final node in graph.nodes) {
    if (!registry.containsKey(node.kind)) {
      issues.add(
        GraphIssue(
          GraphIssueKind.unknownNodeKind,
          'node "${node.id}" has unknown kind "${node.kind}"',
          nodeId: node.id,
        ),
      );
    }
  }

  if (graph.entryNodeId == null || graph.nodeById(graph.entryNodeId!) == null) {
    issues.add(
      const GraphIssue(
        GraphIssueKind.missingEntry,
        'the graph has no entry node, or its entryNodeId does not name a '
        'node that exists',
      ),
    );
  }

  for (final edge in graph.edges) {
    final fromType = _outputPortType(
      graph,
      registry,
      edge.fromNode,
      edge.fromPort,
    );
    final toType = _inputPortType(graph, registry, edge.toNode, edge.toPort);
    if (fromType == null) {
      issues.add(
        GraphIssue(
          GraphIssueKind.unknownPort,
          'edge from "${edge.fromNode}" names output port '
          '"${edge.fromPort}", which that node does not have',
          nodeId: edge.fromNode,
        ),
      );
      continue;
    }
    if (toType == null) {
      issues.add(
        GraphIssue(
          GraphIssueKind.unknownPort,
          'edge to "${edge.toNode}" names input port "${edge.toPort}", '
          'which that node does not have',
          nodeId: edge.toNode,
        ),
      );
      continue;
    }
    if (fromType != toType) {
      issues.add(
        GraphIssue(
          GraphIssueKind.portTypeMismatch,
          '"${edge.fromNode}.${edge.fromPort}" (${fromType.name}) cannot '
          'connect to "${edge.toNode}.${edge.toPort}" (${toType.name})',
          nodeId: edge.fromNode,
        ),
      );
    }
  }

  if (graph.entryNodeId != null && graph.nodeById(graph.entryNodeId!) != null) {
    final reachable = <String>{graph.entryNodeId!};
    final queue = [graph.entryNodeId!];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final edge in graph.outgoingFrom(current)) {
        if (reachable.add(edge.toNode)) queue.add(edge.toNode);
      }
    }
    for (final node in graph.nodes) {
      if (!reachable.contains(node.id)) {
        issues.add(
          GraphIssue(
            GraphIssueKind.unreachableNode,
            'node "${node.id}" is not reachable from the entry node',
            nodeId: node.id,
          ),
        );
      }
    }
  }

  for (final cycle in _findCycles(graph)) {
    final hasWait = cycle.any((id) => graph.nodeById(id)?.kind == 'wait');
    if (!hasWait) {
      issues.add(
        GraphIssue(
          GraphIssueKind.cycleWithoutWait,
          'nodes ${cycle.join(' -> ')} form a cycle with no "wait" node in '
          'it, so a compiled version of it would never yield',
          nodeId: cycle.first,
        ),
      );
    }
  }

  return issues;
}

PortType? _outputPortType(
  Graph graph,
  Map<String, NodeKind> registry,
  String nodeId,
  String portName,
) {
  final node = graph.nodeById(nodeId);
  if (node == null) return null;
  if (node.kind == 'choice') {
    final choices = node.params['choices'] as List? ?? const [];
    for (final choice in choices) {
      if ((choice as Map)['id'] == portName) return PortType.flow;
    }
    return null;
  }
  return registry[node.kind]?.outputNamed(portName)?.type;
}

PortType? _inputPortType(
  Graph graph,
  Map<String, NodeKind> registry,
  String nodeId,
  String portName,
) {
  final node = graph.nodeById(nodeId);
  if (node == null) return null;
  return registry[node.kind]?.inputNamed(portName)?.type;
}

/// Every simple cycle in [graph]'s flow edges, as the node ids around it
/// (starting from whichever node in it sorts first, so the same cycle is
/// always reported the same way regardless of which node a search visits
/// first). Not exhaustive for graphs with many overlapping cycles through
/// the same nodes — it finds one representative cycle per strongly
/// connected component with more than one node, which is enough to flag
/// "this will spin forever," not to enumerate every possible loop.
List<List<String>> _findCycles(Graph graph) {
  final cycles = <List<String>>[];
  final visited = <String>{};

  List<String>? findCycleFrom(String start) {
    final stack = [start];
    final onStack = {start};
    final parent = <String, String>{};

    List<String>? dfs(String node) {
      for (final edge in graph.outgoingFrom(node)) {
        if (edge.toNode == start && stack.length > 0) {
          return [...stack];
        }
        if (onStack.contains(edge.toNode)) continue;
        if (visited.contains(edge.toNode)) continue;
        stack.add(edge.toNode);
        onStack.add(edge.toNode);
        parent[edge.toNode] = node;
        final found = dfs(edge.toNode);
        if (found != null) return found;
        stack.removeLast();
        onStack.remove(edge.toNode);
      }
      return null;
    }

    return dfs(start);
  }

  final sortedIds = graph.nodes.map((n) => n.id).toList()..sort();
  for (final id in sortedIds) {
    if (visited.contains(id)) continue;
    final cycle = findCycleFrom(id);
    if (cycle != null) {
      cycles.add(cycle);
      visited.addAll(cycle);
    } else {
      visited.add(id);
    }
  }
  return cycles;
}
