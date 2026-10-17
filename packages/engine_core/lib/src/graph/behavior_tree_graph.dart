import 'package:engine_schema/engine_schema.dart';

import 'graph.dart';
import 'graph_validator.dart';
import 'node_kind.dart';

/// Behavior trees and state machines as [Graph]s, so the studio's one graph canvas
/// edits them like any other graph, and compile to the JSON the engine already
/// loads (`BTNode.fromJson`, `StateMachine.fromJson`).
///
/// A **behavior tree** graph: the root is the graph's `entryNodeId`; a composite's
/// `children` output (or a decorator's `child` output) connects to each child's `in`
/// input. Children run in the order [compileBehaviorTree] is given (the studio
/// passes the canvas x position, so left-to-right on screen is first-to-last).
///
/// A **state machine** graph: `state` nodes, joined by `transition` nodes - a
/// transition sits *between* two states (`state.out -> transition.in`,
/// `transition.out -> state.in`) so its `condition` is an ordinary node parameter
/// the inspector can edit.

const _flow = PortType.flow;

NodeKind _composite(String name, [List<FieldSchema> params = const []]) => NodeKind(
      name: name,
      inputs: const [GraphPort('in', _flow)],
      outputs: const [GraphPort('children', _flow)],
      paramsSchema: params,
    );

NodeKind _decorator(String name, [List<FieldSchema> params = const []]) => NodeKind(
      name: name,
      inputs: const [GraphPort('in', _flow)],
      outputs: const [GraphPort('child', _flow)],
      paramsSchema: params,
    );

NodeKind _leaf(String name, [List<FieldSchema> params = const []]) => NodeKind(
      name: name,
      inputs: const [GraphPort('in', _flow)],
      paramsSchema: params,
    );

/// Every behavior-tree node type the engine can load, with the parameters the
/// inspector offers. Names are the `type` strings of the engine's JSON.
final Map<String, NodeKind> behaviorTreeNodeKinds = {
  'sequence': _composite('sequence'),
  'selector': _composite('selector'),
  'randomSequence': _composite('randomSequence'),
  'randomSelector': _composite('randomSelector'),
  'parallel': _composite('parallel', const [
    FieldSchema('requiredSuccess', FieldType.int, min: 1, defaultValue: 1),
  ]),
  'inverter': _decorator('inverter'),
  'succeeder': _decorator('succeeder'),
  'failer': _decorator('failer'),
  'untilSuccess': _decorator('untilSuccess'),
  'untilFailure': _decorator('untilFailure'),
  'repeater': _decorator('repeater', const [
    FieldSchema('count', FieldType.int, min: 0, defaultValue: 1),
  ]),
  'timeout': _decorator('timeout', const [
    FieldSchema('timeoutDuration', FieldType.double, min: 0, defaultValue: 1.0),
  ]),
  'throttle': _decorator('throttle', const [
    FieldSchema('maxRunsPerTick', FieldType.int, min: 1, defaultValue: 1),
  ]),
  'leaf': _leaf('leaf', const [
    FieldSchema('behaviorId', FieldType.string, required: true),
  ]),
  'wait': _leaf('wait', const [
    FieldSchema('duration', FieldType.double, min: 0, defaultValue: 1.0),
  ]),
  'cooldown': _leaf('cooldown', const [
    FieldSchema('behaviorId', FieldType.string, required: true),
    FieldSchema('cooldownDuration', FieldType.double, min: 0, defaultValue: 1.0),
  ]),
  'timer': _leaf('timer', const [
    FieldSchema('duration', FieldType.double, min: 0, defaultValue: 1.0),
    FieldSchema('repeat', FieldType.bool, defaultValue: false),
  ]),
};

/// The node kinds of a state-machine graph.
final Map<String, NodeKind> stateMachineNodeKinds = {
  'state': const NodeKind(
    name: 'state',
    inputs: [GraphPort('in', _flow)],
    outputs: [GraphPort('out', _flow)],
    paramsSchema: [
      FieldSchema('name', FieldType.string, required: true),
      FieldSchema('behaviorTreeGraph', FieldType.string, optional: true),
    ],
  ),
  'transition': const NodeKind(
    name: 'transition',
    inputs: [GraphPort('in', _flow)],
    outputs: [GraphPort('out', _flow)],
    paramsSchema: [FieldSchema('condition', FieldType.string, required: true)],
  ),
};

/// Which family of graph a document is. Decides the node-kind registry, how it
/// compiles, and what the studio's "add node" menu offers.
enum GraphType {
  /// Dialogue / cutscene flow - the original graph kind; the default.
  dialogue,
  behaviorTree,
  stateMachine;

  /// The node-kind registry for this type.
  Map<String, NodeKind> get registry => switch (this) {
        GraphType.dialogue => builtinNodeKinds,
        GraphType.behaviorTree => behaviorTreeNodeKinds,
        GraphType.stateMachine => stateMachineNodeKinds,
      };

  static GraphType parse(Object? name) =>
      GraphType.values.firstWhere((t) => t.name == name, orElse: () => GraphType.dialogue);
}

/// Why a graph cannot be turned into engine JSON. [message] names the node.
class GraphCompileException implements Exception {
  final String message;
  final String? nodeId;
  const GraphCompileException(this.message, {this.nodeId});

  @override
  String toString() => 'GraphCompileException: $message';
}

/// Problems that stop a behavior-tree [graph] compiling, as human-readable issues
/// (empty when it will compile). A superset of the generic graph checks: it also
/// knows a decorator needs exactly one child and a leaf none.
List<GraphIssue> validateBehaviorTree(Graph graph) {
  final issues = <GraphIssue>[];
  GraphIssue issue(GraphIssueKind kind, String message, [String? node]) =>
      GraphIssue(kind, message, nodeId: node);

  final root = graph.entryNodeId == null ? null : graph.nodeById(graph.entryNodeId!);
  if (root == null) {
    issues.add(issue(GraphIssueKind.missingEntry, 'the tree has no root node'));
  }
  for (final node in graph.nodes) {
    final kind = behaviorTreeNodeKinds[node.kind];
    if (kind == null) {
      issues.add(issue(GraphIssueKind.unknownNodeKind, 'node "${node.id}" has unknown kind "${node.kind}"', node.id));
      continue;
    }
    final children = graph.outgoingFrom(node.id).length;
    final isDecorator = kind.outputNamed('child') != null;
    final isComposite = kind.outputNamed('children') != null;
    if (isDecorator && children != 1) {
      issues.add(issue(GraphIssueKind.unknownPort,
          '"${node.id}" (${node.kind}) needs exactly one child, has $children', node.id));
    }
    if (isComposite && children == 0) {
      issues.add(issue(GraphIssueKind.unknownPort, '"${node.id}" (${node.kind}) has no children', node.id));
    }
    if (!isDecorator && !isComposite && children > 0) {
      issues.add(issue(GraphIssueKind.unknownPort, '"${node.id}" (${node.kind}) is a leaf and cannot have children', node.id));
    }
    final parents = graph.edges.where((e) => e.toNode == node.id).length;
    if (parents > 1) {
      issues.add(issue(GraphIssueKind.unknownPort, '"${node.id}" has $parents parents; a tree node has one', node.id));
    }
  }
  if (root != null) {
    final seen = <String>{};
    final stack = [root.id];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (!seen.add(id)) {
        issues.add(issue(GraphIssueKind.cycleWithoutWait, 'the tree loops back to "$id"', id));
        continue;
      }
      stack.addAll(graph.outgoingFrom(id).map((e) => e.toNode));
    }
    for (final node in graph.nodes) {
      if (!seen.contains(node.id)) {
        issues.add(issue(GraphIssueKind.unreachableNode, 'node "${node.id}" is not connected to the root', node.id));
      }
    }
  }
  return issues;
}

/// Compiles a behavior-tree [graph] to the JSON `BTNode.fromJson` loads.
///
/// [order] gives each node a sort key deciding the order of a parent's children
/// (lowest first); the studio passes the canvas x position. Nodes without a key keep
/// the order their edges were drawn in. Throws [GraphCompileException] when the tree
/// under the root has errors per [validateBehaviorTree]; nodes not connected to the
/// root are left out, whatever state they are in.
Map<String, dynamic> compileBehaviorTree(Graph graph, {Map<String, double> order = const {}}) {
  // Only the part of the graph hanging off the root can affect the result, so only
  // its mistakes block the compile. A half-built orphan (a decorator with no child
  // yet) is the editor's business, not a reason to refuse exporting the tree.
  final reachable = <String>{};
  if (graph.entryNodeId != null) {
    final stack = [graph.entryNodeId!];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (reachable.add(id)) stack.addAll(graph.outgoingFrom(id).map((e) => e.toNode));
    }
  }
  final errors = validateBehaviorTree(graph).where((i) =>
      i.kind != GraphIssueKind.unreachableNode && (i.nodeId == null || reachable.contains(i.nodeId)));
  if (errors.isNotEmpty) {
    throw GraphCompileException(errors.first.message, nodeId: errors.first.nodeId);
  }
  Map<String, dynamic> build(String id) {
    final node = graph.nodeById(id)!;
    final kind = behaviorTreeNodeKinds[node.kind]!;
    final kids = graph.outgoingFrom(id).map((e) => e.toNode).toList();
    // Stable sort: equal keys (or no key) keep edge order.
    final indexed = [for (var i = 0; i < kids.length; i++) (i, kids[i])]
      ..sort((a, b) {
        final c = (order[a.$2] ?? 0).compareTo(order[b.$2] ?? 0);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final json = <String, dynamic>{'type': node.kind, 'id': node.id};
    for (final field in kind.paramsSchema) {
      final value = node.params[field.name] ?? field.defaultValue;
      if (value != null) json[field.name] = value;
    }
    if (kind.outputNamed('children') != null) {
      json['children'] = [for (final k in indexed) build(k.$2)];
    } else if (kind.outputNamed('child') != null) {
      json['child'] = build(indexed.single.$2);
    }
    return json;
  }

  return build(graph.entryNodeId!);
}

/// A behavior tree turned into a graph, plus where to draw each node.
class ImportedGraph {
  final Graph graph;

  /// Node id -> (x, y) in canvas units.
  final Map<String, (double, double)> layout;
  const ImportedGraph(this.graph, this.layout);
}

/// Builds a graph from engine behavior-tree JSON (`BTNode.toJson` output), laid out as
/// a tree: depth down the page, siblings left to right. The inverse of
/// [compileBehaviorTree]. Node ids are kept (a missing `id` gets a generated one).
ImportedGraph graphFromBehaviorTree(
  Map<String, dynamic> json, {
  double columnWidth = 180,
  double rowHeight = 110,
}) {
  final nodes = <GraphNode>[];
  final edges = <GraphEdge>[];
  final layout = <String, (double, double)>{};
  final usedIds = <String>{};
  var nextColumn = 0;

  String uniqueId(String? wanted, String type) {
    var id = (wanted == null || wanted.isEmpty) ? type : wanted;
    var n = 1;
    final base = id;
    while (!usedIds.add(id)) {
      id = '$base${n++}';
    }
    return id;
  }

  // Returns the node id and the x position of its subtree's center.
  (String, double) visit(Map<String, dynamic> j, int depth) {
    final type = j['type'] as String? ?? (throw const FormatException('a node has no "type"'));
    final kind = behaviorTreeNodeKinds[type] ?? (throw FormatException('unknown node type "$type"'));
    final id = uniqueId(j['id'] as String?, type);
    final params = <String, dynamic>{
      for (final field in kind.paramsSchema)
        if (j.containsKey(field.name)) field.name: j[field.name],
    };
    nodes.add(GraphNode(id: id, kind: type, params: params));

    final childJson = <Map<String, dynamic>>[
      if (j['children'] is List) for (final c in j['children'] as List) (c as Map).cast<String, dynamic>(),
      if (j['child'] is Map) (j['child'] as Map).cast<String, dynamic>(),
    ];
    final port = kind.outputNamed('children')?.name ?? kind.outputNamed('child')?.name;
    final xs = <double>[];
    for (final c in childJson) {
      final (childId, x) = visit(c, depth + 1);
      xs.add(x);
      edges.add(GraphEdge(fromNode: id, fromPort: port!, toNode: childId, toPort: 'in'));
    }
    final x = xs.isEmpty ? (nextColumn++) * columnWidth : (xs.first + xs.last) / 2;
    layout[id] = (x, depth * rowHeight);
    return (id, x);
  }

  final (rootId, _) = visit(json, 0);
  return ImportedGraph(Graph(nodes: nodes, edges: edges, entryNodeId: rootId), layout);
}

/// Compiles a state-machine [graph] to the JSON `StateMachine.fromJson` loads.
///
/// The first `state` node (or [Graph.entryNodeId] if set) is the initial state.
/// [resolveTree] supplies the compiled behavior tree for a state's
/// `behaviorTreeGraph` parameter (a project path); it may return null to leave the
/// state without one.
///
/// A transition's `condition` is written as a **name** next to `toState`. The engine
/// does not serialize condition code (`FSMTransition.toJson` drops it; `fromJson`
/// loads a never-true placeholder), so the game binds each name to a real function
/// when it builds the machine - the studio's job is to author the names and the
/// wiring, not the logic.
Map<String, dynamic> compileStateMachine(
  Graph graph, {
  String id = 'fsm',
  Map<String, dynamic>? Function(String graphPath)? resolveTree,
}) {
  final states = graph.nodes.where((n) => n.kind == 'state').toList();
  if (states.isEmpty) throw const GraphCompileException('a state machine needs at least one state');
  final names = <String, String>{}; // node id -> state name
  for (final s in states) {
    final name = (s.params['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw GraphCompileException('state "${s.id}" has no name', nodeId: s.id);
    }
    if (names.containsValue(name)) {
      throw GraphCompileException('two states are named "$name"', nodeId: s.id);
    }
    names[s.id] = name;
  }

  final out = <String, dynamic>{};
  for (final s in states) {
    final transitions = <String, dynamic>{};
    for (final toTransition in graph.outgoingFrom(s.id)) {
      final t = graph.nodeById(toTransition.toNode);
      if (t == null || t.kind != 'transition') {
        throw GraphCompileException(
            '"${s.id}" connects straight to "${toTransition.toNode}"; go through a transition node',
            nodeId: s.id);
      }
      final targets = graph.outgoingFrom(t.id);
      if (targets.length != 1 || names[targets.single.toNode] == null) {
        throw GraphCompileException('transition "${t.id}" must lead to exactly one state', nodeId: t.id);
      }
      final to = names[targets.single.toNode]!;
      if (transitions.containsKey(to)) {
        throw GraphCompileException('"${names[s.id]}" has two transitions to "$to"', nodeId: t.id);
      }
      transitions[to] = {'toState': to, 'condition': t.params['condition'] ?? ''};
    }
    final treePath = s.params['behaviorTreeGraph'] as String?;
    out[names[s.id]!] = {
      'name': names[s.id],
      'behaviorTree': treePath == null || treePath.isEmpty ? null : resolveTree?.call(treePath),
      'transitions': transitions,
    };
  }
  final initial = graph.entryNodeId != null ? names[graph.entryNodeId!] : null;
  return {
    'id': id,
    'currentState': initial ?? names[states.first.id],
    'states': out,
  };
}
