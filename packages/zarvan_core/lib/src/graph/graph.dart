/// The kind of value a graph port carries. `flow` ports are the control-flow
/// wires between nodes (which one runs next); the rest are the data a node's
/// `params` reference, for the validator to type-check an edge against.
enum PortType { flow, string, number, boolean, entity, event }

/// One node in a [Graph]: its [kind] (a name in the `NodeKind` registry —
/// `node_kind.dart`) and the parameters an editor fills in for it (e.g. a
/// `say` node's `textKey`). Position is deliberately not here — that's
/// presentation state for the studio's canvas, not part of what the graph
/// means, and keeping it out means a hand-written graph (as in most tests)
/// never has to supply layout it doesn't care about.
class GraphNode {
  final String id;
  final String kind;
  final Map<String, dynamic> params;

  const GraphNode({
    required this.id,
    required this.kind,
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    if (params.isNotEmpty) 'params': params,
  };

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
    id: json['id'] as String,
    kind: json['kind'] as String,
    params: (json['params'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

/// A directed connection from one node's output port to another's input
/// port. Both ports are named, not indexed, so a node kind can add a port
/// without shifting the meaning of every edge already pointing at the ones
/// after it.
class GraphEdge {
  final String fromNode;
  final String fromPort;
  final String toNode;
  final String toPort;

  const GraphEdge({
    required this.fromNode,
    required this.fromPort,
    required this.toNode,
    required this.toPort,
  });

  Map<String, dynamic> toJson() => {
    'fromNode': fromNode,
    'fromPort': fromPort,
    'toNode': toNode,
    'toPort': toPort,
  };

  factory GraphEdge.fromJson(Map<String, dynamic> json) => GraphEdge(
    fromNode: json['fromNode'] as String,
    fromPort: json['fromPort'] as String,
    toNode: json['toNode'] as String,
    toPort: json['toPort'] as String,
  );
}

/// A named value a graph's nodes can read or write (`GetVar`/`SetVar`),
/// scoped to the one graph that declares it.
class GraphVariable {
  final String name;
  final PortType type;
  final Object? initialValue;

  const GraphVariable({
    required this.name,
    required this.type,
    this.initialValue,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    if (initialValue != null) 'initialValue': initialValue,
  };

  factory GraphVariable.fromJson(Map<String, dynamic> json) => GraphVariable(
    name: json['name'] as String,
    type: PortType.values.byName(json['type'] as String),
    initialValue: json['initialValue'],
  );
}

/// A visual-scripting graph (docs/studio/design.md Phase 4): nodes, the edges
/// between their ports, the variables it declares, and which node execution
/// starts at. Graphs don't run themselves — a compiler
/// (`dialogue_compiler.dart` for now) turns one into the runtime primitives
/// that already exist (D3: compile-only, no parallel interpreter), the same
/// way `LevelDocument` is data a level needs `Level.loadInto` to act on.
class Graph {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<GraphVariable> variables;
  final String? entryNodeId;

  const Graph({
    this.nodes = const [],
    this.edges = const [],
    this.variables = const [],
    this.entryNodeId,
  });

  Map<String, dynamic> toJson() => {
    'nodes': [for (final n in nodes) n.toJson()],
    'edges': [for (final e in edges) e.toJson()],
    if (variables.isNotEmpty)
      'variables': [for (final v in variables) v.toJson()],
    if (entryNodeId != null) 'entryNodeId': entryNodeId,
  };

  factory Graph.fromJson(Map<String, dynamic> json) => Graph(
    nodes: [
      for (final n in (json['nodes'] as List))
        GraphNode.fromJson((n as Map).cast<String, dynamic>()),
    ],
    edges: [
      for (final e in (json['edges'] as List? ?? const []))
        GraphEdge.fromJson((e as Map).cast<String, dynamic>()),
    ],
    variables: [
      for (final v in (json['variables'] as List? ?? const []))
        GraphVariable.fromJson((v as Map).cast<String, dynamic>()),
    ],
    entryNodeId: json['entryNodeId'] as String?,
  );

  /// The node with [id], or null when there is none.
  GraphNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// Every edge leaving [nodeId], regardless of which of its output ports.
  List<GraphEdge> outgoingFrom(String nodeId) => [
    for (final e in edges)
      if (e.fromNode == nodeId) e,
  ];

  /// The edge leaving [nodeId] by [portName], or null when that port has no
  /// outgoing connection.
  GraphEdge? outgoingPort(String nodeId, String portName) {
    for (final e in edges) {
      if (e.fromNode == nodeId && e.fromPort == portName) return e;
    }
    return null;
  }
}
