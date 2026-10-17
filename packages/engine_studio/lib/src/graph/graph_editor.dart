import 'dart:ui';

import 'package:engine_core/engine_core.dart';

/// Where [GraphEditor.layout] was in the saved file — not part of [Graph]
/// itself, since node position is the studio canvas's presentation state,
/// not part of what the graph means to the compiler (see `graph.dart`'s own
/// doc comment on this). A `GraphDocument` is what actually gets saved to
/// `graphs/*.json`: the graph plus this layout, side by side.
class GraphDocument {
  final Graph graph;
  final Map<String, Offset> layout;

  const GraphDocument({required this.graph, this.layout = const {}});

  Map<String, dynamic> toJson() => {
    'graph': graph.toJson(),
    if (layout.isNotEmpty)
      'layout': {
        for (final entry in layout.entries)
          entry.key: [entry.value.dx, entry.value.dy],
      },
  };

  factory GraphDocument.fromJson(Map<String, dynamic> json) => GraphDocument(
    graph: Graph.fromJson((json['graph'] as Map).cast<String, dynamic>()),
    layout: {
      for (final entry in (json['layout'] as Map? ?? const {}).entries)
        entry.key as String: Offset(
          ((entry.value as List)[0] as num).toDouble(),
          (entry.value[1] as num).toDouble(),
        ),
    },
  );
}

/// The editing session for one graph: a mutable node/edge/variable list (so
/// the canvas can add, move, and connect things) plus each node's canvas
/// position. Builds an immutable [Graph] snapshot on demand via [graph],
/// the same split `LevelEditor`/`LevelDocument` use.
///
/// `GraphKind` here means dialogue-only, cutscene-only, etc. isn't
/// enforced by this editor — [NodeKind]'s registry decides what a node
/// kind even is; a project can register kinds beyond the built-ins.
class GraphEditor {
  final List<GraphNode> _nodes = [];
  final List<GraphEdge> _edges = [];
  final List<GraphVariable> _variables = [];
  String? entryNodeId;
  final Map<String, Offset> layout = {};
  final Map<String, NodeKind> registry;

  String? selectedNodeId;

  /// An output port the designer has clicked, waiting for a matching input
  /// port to click next — click-to-connect rather than drag-to-connect (see
  /// `graph_canvas.dart`'s own doc comment on why).
  (String nodeId, String port)? armedOutput;

  String? lastError;

  GraphEditor({this.registry = builtinNodeKinds});

  factory GraphEditor.fromDocument(
    GraphDocument document, {
    Map<String, NodeKind> registry = builtinNodeKinds,
  }) {
    final editor = GraphEditor(registry: registry);
    editor._nodes.addAll(document.graph.nodes);
    editor._edges.addAll(document.graph.edges);
    editor._variables.addAll(document.graph.variables);
    editor.entryNodeId = document.graph.entryNodeId;
    editor.layout.addAll(document.layout);
    return editor;
  }

  List<GraphNode> get nodes => List.unmodifiable(_nodes);
  List<GraphEdge> get edges => List.unmodifiable(_edges);
  List<GraphVariable> get variables => List.unmodifiable(_variables);

  Graph get graph => Graph(
    nodes: List.of(_nodes),
    edges: List.of(_edges),
    variables: List.of(_variables),
    entryNodeId: entryNodeId,
  );

  GraphDocument get document => GraphDocument(graph: graph, layout: Map.of(layout));

  List<GraphIssue> validate() => validateGraph(graph, registry: registry);

  GraphNode? nodeById(String id) => graph.nodeById(id);

  /// Adds a node of [kind] at [position], with an auto-generated id unique
  /// in this graph. The first node added becomes the entry automatically,
  /// since a graph with nodes but no entry is always a validation error
  /// anyway.
  GraphNode addNode(String kind, Offset position) {
    var index = _nodes.length;
    var id = '$kind$index';
    while (_nodes.any((n) => n.id == id)) {
      index++;
      id = '$kind$index';
    }
    final node = GraphNode(id: id, kind: kind);
    _nodes.add(node);
    layout[id] = position;
    entryNodeId ??= id;
    return node;
  }

  /// Removes [nodeId] and every edge touching it. Clears the entry and/or
  /// selection if either pointed at it.
  void removeNode(String nodeId) {
    _nodes.removeWhere((n) => n.id == nodeId);
    _edges.removeWhere((e) => e.fromNode == nodeId || e.toNode == nodeId);
    layout.remove(nodeId);
    if (entryNodeId == nodeId) entryNodeId = null;
    if (selectedNodeId == nodeId) selectedNodeId = null;
    if (armedOutput?.$1 == nodeId) armedOutput = null;
  }

  void moveNode(String nodeId, Offset position) {
    layout[nodeId] = position;
  }

  void select(String? nodeId) {
    selectedNodeId = nodeId;
  }

  /// Replaces [nodeId]'s params (e.g. from the inspector).
  void setParams(String nodeId, Map<String, dynamic> params) {
    final index = _nodes.indexWhere((n) => n.id == nodeId);
    if (index < 0) return;
    _nodes[index] = GraphNode(id: nodeId, kind: _nodes[index].kind, params: params);
  }

  /// Click-to-connect: call once with an output port to arm it, then again
  /// with an input port to complete the edge. Connecting the armed output
  /// to anything other than an input port, or to a port whose type doesn't
  /// match, sets [lastError] and disarms without changing the graph —
  /// clicking is cheap to retry, so this fails loudly rather than guessing.
  void clickPort(String nodeId, String portName, {required bool isOutput}) {
    lastError = null;
    final armed = armedOutput;
    if (armed == null) {
      if (!isOutput) {
        lastError = 'click an output port first, then the input to connect it to';
        return;
      }
      armedOutput = (nodeId, portName);
      return;
    }
    armedOutput = null;
    if (isOutput) {
      lastError = 'that is another output port — click an input port to finish the connection';
      return;
    }
    final fromType = _outputPortType(armed.$1, armed.$2);
    final toType = _inputPortType(nodeId, portName);
    if (fromType == null || toType == null) {
      lastError = 'one of those ports does not exist on its node';
      return;
    }
    if (fromType != toType) {
      lastError =
          'cannot connect a ${fromType.name} output to a ${toType.name} input';
      return;
    }
    _edges.removeWhere((e) => e.toNode == nodeId && e.toPort == portName);
    _edges.add(
      GraphEdge(fromNode: armed.$1, fromPort: armed.$2, toNode: nodeId, toPort: portName),
    );
  }

  void cancelArmedPort() => armedOutput = null;

  void disconnect(GraphEdge edge) {
    _edges.remove(edge);
  }

  PortType? _outputPortType(String nodeId, String portName) {
    final node = nodeById(nodeId);
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

  PortType? _inputPortType(String nodeId, String portName) {
    final node = nodeById(nodeId);
    if (node == null) return null;
    return registry[node.kind]?.inputNamed(portName)?.type;
  }
}
