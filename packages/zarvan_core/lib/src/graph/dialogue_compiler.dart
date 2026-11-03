import '../content/dialogue.dart';
import 'graph.dart';

/// Thrown by [compileDialogueGraph] when [Graph] contains something this
/// compiler doesn't know how to turn into dialogue primitives. Compiling is
/// expected to fail loudly on a graph it can't handle, not guess.
class DialogueCompileError implements Exception {
  final String message;
  const DialogueCompileError(this.message);

  @override
  String toString() => 'DialogueCompileError: $message';
}

/// The only node kinds [compileDialogueGraph] understands. `setVar`/
/// `getVar`/`branch`/`wait`/`playCinematic`/`emitEvent`/`spawnEntity` are
/// real, registered node kinds (`node_kind.dart`) a graph can use and the
/// validator can check — they just don't have a dialogue-primitive
/// translation yet. A graph that mixes them into a dialogue subgraph is a
/// compile error, not a silently wrong `DialogueGraph`.
const _dialogueNodeKinds = {'say', 'choice'};

/// Compiles a dialogue-only [Graph] (D3: compile to existing primitives, no
/// parallel interpreter) into the [DialogueGraph] `DialogueRunner` already
/// knows how to run.
///
/// - A `say` node becomes a [DialogueNode] with [DialogueNode.textKey] and
///   [DialogueNode.speaker] from its params. If it has an outgoing edge
///   (on its single `out` port), it gets one synthetic, always-available
///   [DialogueChoice] (empty text, an empty event) pointing at that edge's
///   target, with [DialogueNode.autoAdvance] set so nothing has to tap
///   through a choice that was never really there — a `say` node is linear
///   narration, not a decision point. No outgoing edge means the node ends
///   the dialogue, the same as any node with no choices.
/// - A `choice` node becomes a [DialogueNode] whose real text comes from
///   `params['textKey']` and whose [DialogueNode.choices] are built from
///   `params['choices']` (each `{id, textKey, conditionExpression?}`),
///   wired to whichever node each entry's `id`-named output port connects
///   to.
DialogueGraph compileDialogueGraph(Graph graph) {
  final entry = graph.entryNodeId;
  if (entry == null || graph.nodeById(entry) == null) {
    throw const DialogueCompileError(
      'the graph has no entry node, or its entryNodeId does not name a '
      'node that exists',
    );
  }

  final nodes = <String, DialogueNode>{};
  for (final node in graph.nodes) {
    if (!_dialogueNodeKinds.contains(node.kind)) {
      throw DialogueCompileError(
        'node "${node.id}" has kind "${node.kind}", which the dialogue '
        'compiler does not support (only say/choice compile to dialogue '
        'primitives)',
      );
    }
    nodes[node.id] = node.kind == 'say'
        ? _compileSay(graph, node)
        : _compileChoice(graph, node);
  }

  return DialogueGraph(nodes: nodes, startNodeId: entry);
}

DialogueNode _compileSay(Graph graph, GraphNode node) {
  final edge = graph.outgoingPort(node.id, 'out');
  return DialogueNode(
    id: node.id,
    textKey: node.params['textKey'] as String? ?? '',
    speaker: node.params['speaker'] as String?,
    portrait: node.params['portrait'] as String?,
    choices: edge == null
        ? const []
        : [
            DialogueChoice(
              textKey: '',
              onSelectEvent: const <String, dynamic>{},
              nextNodeId: edge.toNode,
            ),
          ],
    autoAdvance: edge != null,
    autoAdvanceDelay: 0,
  );
}

DialogueNode _compileChoice(Graph graph, GraphNode node) {
  final entries = node.params['choices'] as List? ?? const [];
  return DialogueNode(
    id: node.id,
    textKey: node.params['textKey'] as String? ?? '',
    speaker: node.params['speaker'] as String?,
    choices: [
      for (final raw in entries)
        _compileChoiceEntry(graph, node, (raw as Map).cast<String, dynamic>()),
    ],
  );
}

DialogueChoice _compileChoiceEntry(
  Graph graph,
  GraphNode node,
  Map<String, dynamic> entry,
) {
  final portId = entry['id'] as String;
  final edge = graph.outgoingPort(node.id, portId);
  return DialogueChoice(
    textKey: entry['textKey'] as String? ?? '',
    conditionExpression: entry['conditionExpression'] as String?,
    onSelectEvent: entry['onSelectEvent'] ?? const <String, dynamic>{},
    nextNodeId: edge?.toNode,
  );
}
