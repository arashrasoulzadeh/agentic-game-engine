import 'package:engine_schema/engine_schema.dart';

import 'graph.dart';

/// One named port on a [NodeKind]: its name (what a [GraphEdge] points at)
/// and the kind of value it carries.
class GraphPort {
  final String name;
  final PortType type;

  const GraphPort(this.name, this.type);
}

/// The schema for one node kind: its input and output ports. A `choice`
/// node's per-choice outputs aren't fixed ports here — they're declared by
/// that node's own `params['choices']` (see `dialogue_compiler.dart`), one
/// output port per choice entry, named by that entry's `id`. Every other
/// built-in kind's ports are exactly what's listed here.
class NodeKind {
  final String name;
  final List<GraphPort> inputs;
  final List<GraphPort> outputs;

  /// The fields a studio node inspector shows for this kind's `params`,
  /// reusing [FieldSchema] rather than a parallel schema system — the same
  /// fields drive the same `FieldType`-switched controls
  /// `inspector_panel.dart` already builds for level components. `choice`'s
  /// `choices` field is a [FieldType.object] (a list of `{id, textKey,
  /// conditionExpression?}` entries) shown as read-only JSON, the same way
  /// an unschematized shape already is, since it isn't a single scalar
  /// value a text field or dropdown can edit.
  final List<FieldSchema> paramsSchema;

  const NodeKind({
    required this.name,
    this.inputs = const [],
    this.outputs = const [],
    this.paramsSchema = const [],
  });

  GraphPort? inputNamed(String name) {
    for (final port in inputs) {
      if (port.name == name) return port;
    }
    return null;
  }

  GraphPort? outputNamed(String name) {
    for (final port in outputs) {
      if (port.name == name) return port;
    }
    return null;
  }
}

/// The node kinds every studio project gets for free (STUDIO_TODO.md 4.4).
/// A project-specific kind would extend this map, not replace it.
const builtinNodeKinds = <String, NodeKind>{
  'say': NodeKind(
    name: 'say',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
    paramsSchema: [
      FieldSchema('textKey', FieldType.string, required: true),
      FieldSchema('speaker', FieldType.string, optional: true),
      FieldSchema('portrait', FieldType.string, optional: true),
    ],
  ),
  // A choice node's real outputs are one flow port per entry in
  // params['choices'], named by that entry's id — not listed here, since
  // they're per-instance, not per-kind. 'in' is the only port this schema
  // can state once and for all.
  'choice': NodeKind(
    name: 'choice',
    inputs: [GraphPort('in', PortType.flow)],
    paramsSchema: [
      FieldSchema('textKey', FieldType.string, optional: true),
      FieldSchema('choices', FieldType.object, defaultValue: <dynamic>[]),
    ],
  ),
  'setVar': NodeKind(
    name: 'setVar',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
    paramsSchema: [
      FieldSchema('variable', FieldType.string, required: true),
      FieldSchema('value', FieldType.object, defaultValue: null, optional: true),
    ],
  ),
  'getVar': NodeKind(
    name: 'getVar',
    outputs: [GraphPort('value', PortType.string)],
    paramsSchema: [FieldSchema('variable', FieldType.string, required: true)],
  ),
  'branch': NodeKind(
    name: 'branch',
    inputs: [
      GraphPort('in', PortType.flow),
      GraphPort('condition', PortType.boolean),
    ],
    outputs: [
      GraphPort('true', PortType.flow),
      GraphPort('false', PortType.flow),
    ],
  ),
  'wait': NodeKind(
    name: 'wait',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
    paramsSchema: [
      FieldSchema('duration', FieldType.double, min: 0, defaultValue: 1.0),
    ],
  ),
  'playCinematic': NodeKind(
    name: 'playCinematic',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
    paramsSchema: [
      FieldSchema('cinematicId', FieldType.string, required: true),
    ],
  ),
  'emitEvent': NodeKind(
    name: 'emitEvent',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
    paramsSchema: [
      FieldSchema('event', FieldType.object, defaultValue: <String, dynamic>{}),
    ],
  ),
  'spawnEntity': NodeKind(
    name: 'spawnEntity',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
    paramsSchema: [
      FieldSchema('prefabId', FieldType.string, required: true),
    ],
  ),
};
