import 'dart:convert';

import '../../content/level_format.dart';
import '../../graph/behavior_tree_graph.dart';
import '../../graph/graph.dart';
import '../../graph/graph_validator.dart';
import '../../graph/node_kind.dart';
import '../context.dart';
import '../operation.dart';
import '../param.dart';
import '../project/studio_project.dart';
import '../result.dart';

const _path = Param('path', ParamType.path, required: true, positional: true);

/// A graph file as the studio saves it: `{type?, graph: {nodes, edges, variables?, entryNodeId?}, layout?}`.
class _GraphFile {
  _GraphFile(this.rel, this.before, this.json)
    : type = GraphType.parse(json['type']);

  final String rel;
  final String? before;
  final Map<String, dynamic> json;
  final GraphType type;

  Map<String, dynamic> get graphJson =>
      (json['graph'] ??= <String, dynamic>{'nodes': [], 'edges': []})
          as Map<String, dynamic>;
  List<dynamic> get nodes => (graphJson['nodes'] ??= <dynamic>[]) as List;
  List<dynamic> get edges => (graphJson['edges'] ??= <dynamic>[]) as List;
  Graph get graph => Graph.fromJson(graphJson);

  Map<String, NodeKind> get registry => type.registry;

  List<GraphIssue> issues() => switch (type) {
    GraphType.behaviorTree => validateBehaviorTree(graph),
    GraphType.stateMachine => validateStateMachine(graph),
    GraphType.dialogue => validateGraph(graph, registry: registry),
  };

  Map<String, dynamic>? node(String id) {
    for (final n in nodes) {
      if ((n as Map)['id'] == id) return n.cast<String, dynamic>();
    }
    return null;
  }

  FileChange change() =>
      FileChange(path: rel, before: before, after: encodeLevelJson(json));
}

_GraphFile _load(OpContext ctx, String rel) {
  final text = ctx.files.read(ctx.project!.resolve(rel));
  if (text == null) throw OpError(ErrorCode.notFound, 'No file at $rel.');
  try {
    final json = (jsonDecode(text) as Map).cast<String, dynamic>();
    final file = _GraphFile(rel, text, json);
    file.graph;
    return file;
  } on Object catch (e) {
    throw OpError(ErrorCode.validationFailed, '$rel is not a graph file ($e).');
  }
}

Map<String, Object?> _issueJson(GraphIssue i) => {
  'kind': i.kind.name,
  'message': i.message,
  if (i.nodeId != null) 'nodeId': i.nodeId,
};

GraphPort? _port(
  _GraphFile f,
  String nodeId,
  String port, {
  required bool output,
}) {
  final node = f.node(nodeId);
  if (node == null) throw OpError(ErrorCode.notFound, 'No node "$nodeId".');
  final kind = f.registry[node['kind']];
  if (kind == null) {
    throw OpError(
      ErrorCode.invalidParams,
      'Node "$nodeId" has unknown kind "${node['kind']}".',
    );
  }
  if (output && node['kind'] == 'choice') {
    for (final c in (node['params']?['choices'] as List? ?? const [])) {
      if ((c as Map)['id'] == port) return GraphPort(port, PortType.flow);
    }
  }
  return output ? kind.outputNamed(port) : kind.inputNamed(port);
}

OpOutcome _write(_GraphFile f, Object? data) {
  final issues = f.issues();
  return OpOutcome.proposal(
    Proposal([f.change()]),
    data: data,
    warnings: [for (final i in issues) i.message],
  );
}

const _edgeParams = [
  _path,
  Param('from', ParamType.string, required: true),
  Param('fromPort', ParamType.string, required: true),
  Param('to', ParamType.string, required: true),
  Param('toPort', ParamType.string, required: true),
];

/// `graph.*`: visual-scripting graphs (`graphs/*.json`): dialogue, behavior trees and state machines.
List<Operation> graphOperations() => [
  Operation(
    name: 'graph.list',
    summary: 'List the project\'s graphs with their type and node count.',
    description: 'Every `graphs/*.json`.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) {
      final project = StudioProject.open(ctx.project!.root);
      return OpOutcome.data([
        for (final rel in project.graphPaths())
          () {
            try {
              final f = _load(ctx, rel);
              return {
                'path': rel,
                'type': f.type.name,
                'nodes': f.nodes.length,
              };
            } on OpError catch (e) {
              return {'path': rel, 'error': e.message};
            }
          }(),
      ]);
    },
  ),
  Operation(
    name: 'graph.read',
    summary: 'Read a graph file.',
    description:
        'The file as saved: type, graph (nodes, edges, variables, entryNodeId) and canvas layout.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [_path],
    handler: (ctx, a) => OpOutcome.data(_load(ctx, a['path']! as String).json),
  ),
  Operation(
    name: 'graph.node_kinds',
    summary:
        'The node kinds available for a graph type, with ports and parameters.',
    description:
        'Ports are typed (flow, string, number, boolean, entity, event); `connect` only joins equal types.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param(
        'type',
        ParamType.enumeration,
        options: ['dialogue', 'behaviorTree', 'stateMachine'],
        defaultValue: 'dialogue',
        positional: true,
      ),
    ],
    handler: (ctx, a) => OpOutcome.data([
      for (final k in GraphType.parse(a['type']).registry.values)
        {
          'name': k.name,
          'inputs': [
            for (final p in k.inputs) {'name': p.name, 'type': p.type.name},
          ],
          'outputs': [
            for (final p in k.outputs) {'name': p.name, 'type': p.type.name},
          ],
          'params': [
            for (final f in k.paramsSchema)
              {
                'name': f.name,
                'type': f.type.name,
                'required': f.required,
                if (f.defaultValue != null) 'default': f.defaultValue,
                if (f.options.isNotEmpty) 'options': f.options,
              },
          ],
        },
    ]),
  ),
  Operation(
    name: 'graph.validate',
    summary:
        'Check a graph for unknown kinds, mismatched ports, unreachable nodes and cycles.',
    description:
        'Uses the checks of the graph\'s type (trees check shape, state machines allow loops). `ok` is false when any issue exists.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [_path],
    handler: (ctx, a) {
      final issues = _load(ctx, a['path']! as String).issues();
      return OpOutcome.data({
        'ok': issues.isEmpty,
        'issues': [for (final i in issues) _issueJson(i)],
      });
    },
  ),
  Operation(
    name: 'graph.compile',
    summary: 'Compile a behavior tree or state machine graph to engine JSON.',
    description:
        'Behavior-tree children follow the canvas left to right. Dialogue graphs have no single compiled form here '
        '(`compiled` is null). With `output` the JSON is also written there.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      _path,
      Param('output', ParamType.path),
      Param('id', ParamType.string, defaultValue: 'fsm'),
    ],
    errors: {
      ErrorCode.validationFailed:
          'The graph cannot be compiled (message names the node).',
    },
    handler: (ctx, a) {
      final f = _load(ctx, a['path']! as String);
      final Map<String, dynamic>? compiled;
      try {
        final layout = (f.json['layout'] as Map?) ?? const {};
        compiled = switch (f.type) {
          GraphType.behaviorTree => compileBehaviorTree(
            f.graph,
            order: {
              for (final e in layout.entries)
                e.key as String: ((e.value as List)[0] as num).toDouble(),
            },
          ),
          GraphType.stateMachine => compileStateMachine(
            f.graph,
            id: a['id']! as String,
          ),
          GraphType.dialogue => null,
        };
      } on GraphCompileException catch (e) {
        throw OpError(
          ErrorCode.validationFailed,
          e.message,
          details: {if (e.nodeId != null) 'nodeId': e.nodeId},
        );
      }
      final out = a['output'] as String?;
      if (out == null || compiled == null) {
        return OpOutcome.data({'compiled': compiled});
      }
      return OpOutcome.proposal(
        Proposal([
          FileChange(
            path: out,
            before: ctx.files.read(ctx.project!.resolve(out)),
            after: encodeLevelJson(compiled),
          ),
        ]),
        data: {'compiled': compiled, 'path': out},
      );
    },
  ),
  Operation(
    name: 'graph.create',
    summary: 'Create an empty graph file.',
    description:
        'Files live under `graphs/`. Fails with `conflict` when the file exists.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      _path,
      Param(
        'type',
        ParamType.enumeration,
        options: ['dialogue', 'behaviorTree', 'stateMachine'],
        defaultValue: 'dialogue',
      ),
    ],
    errors: {ErrorCode.conflict: 'The file already exists.'},
    handler: (ctx, a) {
      final rel = a['path']! as String;
      if (!rel.startsWith('graphs/') || !rel.endsWith('.json')) {
        throw OpError(
          ErrorCode.invalidParams,
          'Graph files live at graphs/<name>.json.',
        );
      }
      if (ctx.files.read(ctx.project!.resolve(rel)) != null) {
        throw OpError(ErrorCode.conflict, '$rel already exists.');
      }
      final type = GraphType.parse(a['type']);
      final json = {
        if (type != GraphType.dialogue) 'type': type.name,
        'graph': {'nodes': [], 'edges': []},
      };
      return OpOutcome.proposal(
        Proposal([FileChange(path: rel, after: encodeLevelJson(json))]),
        data: {'path': rel, 'type': type.name},
      );
    },
  ),
  Operation(
    name: 'graph.add_node',
    summary: 'Add a node of a kind; the first node becomes the entry.',
    description:
        'The id defaults to `<kind><index>`. Parameters start at the kind\'s defaults (non-dialogue graphs) and `params` '
        'overrides them. Problems with the graph so far come back as warnings.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      _path,
      Param('kind', ParamType.string, required: true),
      Param('id', ParamType.string),
      Param('params', ParamType.object),
      Param('x', ParamType.number, defaultValue: 0),
      Param('y', ParamType.number, defaultValue: 0),
    ],
    handler: (ctx, a) {
      final f = _load(ctx, a['path']! as String);
      final kind = a['kind']! as String;
      final spec = f.registry[kind];
      if (spec == null) {
        throw OpError(
          ErrorCode.invalidParams,
          'Unknown node kind "$kind" for a ${f.type.name} graph.',
          hint: 'graph.node_kinds lists them.',
        );
      }
      var id = a['id'] as String?;
      if (id == null) {
        var i = f.nodes.length;
        id = '$kind$i';
        while (f.node(id!) != null) {
          id = '$kind${++i}';
        }
      } else if (f.node(id) != null) {
        throw OpError(ErrorCode.conflict, 'Node "$id" already exists.');
      }
      final params = <String, dynamic>{
        if (f.type != GraphType.dialogue)
          for (final p in spec.paramsSchema)
            if (p.defaultValue != null) p.name: p.defaultValue,
        ...?(a['params'] as Map?)?.cast<String, dynamic>(),
      };
      final node = {
        'id': id,
        'kind': kind,
        if (params.isNotEmpty) 'params': params,
      };
      f.nodes.add(node);
      f.graphJson['entryNodeId'] ??= id;
      (f.json['layout'] ??= <String, dynamic>{})[id] = [a['x'], a['y']];
      return _write(f, {'node': node});
    },
  ),
  Operation(
    name: 'graph.remove_node',
    summary: 'Remove a node and every edge touching it.',
    description:
        'Destructive: previews first. Clears the entry node if it was this one.',
    kind: OperationKind.destructive,
    scope: OperationScope.project,
    params: const [_path, Param('id', ParamType.string, required: true)],
    handler: (ctx, a) {
      final f = _load(ctx, a['path']! as String);
      final id = a['id']! as String;
      final node = f.node(id);
      if (node == null) throw OpError(ErrorCode.notFound, 'No node "$id".');
      f.nodes.remove(node);
      final removedEdges = f.edges
          .where((e) => (e as Map)['fromNode'] == id || e['toNode'] == id)
          .length;
      f.edges.removeWhere(
        (e) => (e as Map)['fromNode'] == id || e['toNode'] == id,
      );
      if (f.graphJson['entryNodeId'] == id) f.graphJson.remove('entryNodeId');
      (f.json['layout'] as Map?)?.remove(id);
      return _write(f, {'removed': node, 'edgesRemoved': removedEdges});
    },
  ),
  Operation(
    name: 'graph.connect',
    summary: 'Connect an output port to an input port of the same type.',
    description:
        'Ports are checked against the node kinds; a mismatch is `validation_failed` and nothing is written.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: _edgeParams,
    handler: (ctx, a) {
      final f = _load(ctx, a['path']! as String);
      final from = _port(
        f,
        a['from']! as String,
        a['fromPort']! as String,
        output: true,
      );
      final to = _port(
        f,
        a['to']! as String,
        a['toPort']! as String,
        output: false,
      );
      if (from == null)
        throw OpError(
          ErrorCode.invalidParams,
          '"${a['from']}" has no output port "${a['fromPort']}".',
        );
      if (to == null)
        throw OpError(
          ErrorCode.invalidParams,
          '"${a['to']}" has no input port "${a['toPort']}".',
        );
      if (from.type != to.type) {
        throw OpError(
          ErrorCode.validationFailed,
          'Cannot connect a ${from.type.name} output to a ${to.type.name} input.',
        );
      }
      final edge = {
        'fromNode': a['from'],
        'fromPort': a['fromPort'],
        'toNode': a['to'],
        'toPort': a['toPort'],
      };
      if (f.edges.any((e) => jsonEncode(e) == jsonEncode(edge))) {
        throw OpError(ErrorCode.conflict, 'That connection already exists.');
      }
      f.edges.add(edge);
      return _write(f, {'edge': edge});
    },
  ),
  Operation(
    name: 'graph.disconnect',
    summary: 'Remove one connection.',
    description:
        'Exact match on both ends; `not_found` when there is no such edge.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: _edgeParams,
    handler: (ctx, a) {
      final f = _load(ctx, a['path']! as String);
      final before = f.edges.length;
      f.edges.removeWhere(
        (e) =>
            (e as Map)['fromNode'] == a['from'] &&
            e['fromPort'] == a['fromPort'] &&
            e['toNode'] == a['to'] &&
            e['toPort'] == a['toPort'],
      );
      if (f.edges.length == before)
        throw OpError(ErrorCode.notFound, 'No such connection.');
      return _write(f, {'removed': true});
    },
  ),
  Operation(
    name: 'graph.set_param',
    summary: 'Set one parameter of a node.',
    description:
        'Free-form: the value is stored as given. Use graph.node_kinds to see what a kind expects.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      _path,
      Param('node', ParamType.string, required: true),
      Param('param', ParamType.string, required: true),
      Param('value', ParamType.json, required: true),
    ],
    handler: (ctx, a) {
      final f = _load(ctx, a['path']! as String);
      final node = f.node(a['node']! as String);
      if (node == null)
        throw OpError(ErrorCode.notFound, 'No node "${a['node']}".');
      final params = (node['params'] ??= <String, dynamic>{}) as Map;
      final before = params[a['param']];
      params[a['param']! as String] = a['value'];
      return _write(f, {'before': before, 'after': a['value']});
    },
  ),
];
