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

  const NodeKind({
    required this.name,
    this.inputs = const [],
    this.outputs = const [],
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
  ),
  // A choice node's real outputs are one flow port per entry in
  // params['choices'], named by that entry's id — not listed here, since
  // they're per-instance, not per-kind. 'in' is the only port this schema
  // can state once and for all.
  'choice': NodeKind(
    name: 'choice',
    inputs: [GraphPort('in', PortType.flow)],
  ),
  'setVar': NodeKind(
    name: 'setVar',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
  ),
  'getVar': NodeKind(
    name: 'getVar',
    outputs: [GraphPort('value', PortType.string)],
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
  ),
  'playCinematic': NodeKind(
    name: 'playCinematic',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
  ),
  'emitEvent': NodeKind(
    name: 'emitEvent',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
  ),
  'spawnEntity': NodeKind(
    name: 'spawnEntity',
    inputs: [GraphPort('in', PortType.flow)],
    outputs: [GraphPort('out', PortType.flow)],
  ),
};
