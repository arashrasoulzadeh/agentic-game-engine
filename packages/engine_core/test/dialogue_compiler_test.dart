import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// Drives a [DialogueRunner] through a fixed script, recording the shown
/// node ids (in order) and ended-state, so a compiled graph's behavior can
/// be compared directly against a hand-written [DialogueGraph]'s.
class _Trace {
  final List<String> shownNodeIds = [];
  bool ended = false;
}

_Trace _runScript(DialogueGraph graph, List<int> choiceIndices) {
  final trace = _Trace();
  final runner = DialogueRunner(
    graph: graph,
    stringTable: StringTable(const {}),
    onNodeShown: (node) => trace.shownNodeIds.add(node.id),
    onEnded: () => trace.ended = true,
  );
  trace.shownNodeIds.add(runner.currentNode!.id);
  final world = World(width: 800, height: 480);
  registerCoreComponents(world);
  for (final index in choiceIndices) {
    runner.advance(world, index);
  }
  return trace;
}

void main() {
  test(
    'docs/studio/design.md 4.7: a compiled dialogue graph behaves the same as '
    'a hand-written one for a linear say -> say script',
    () {
      const graph = Graph(
        nodes: [
          GraphNode(
            id: 'intro',
            kind: 'say',
            params: {'textKey': 'intro.text'},
          ),
          GraphNode(
            id: 'outro',
            kind: 'say',
            params: {'textKey': 'outro.text'},
          ),
        ],
        edges: [
          GraphEdge(
            fromNode: 'intro',
            fromPort: 'out',
            toNode: 'outro',
            toPort: 'in',
          ),
        ],
        entryNodeId: 'intro',
      );
      final compiled = compileDialogueGraph(graph);

      final handWritten = DialogueGraph(
        startNodeId: 'intro',
        nodes: {
          'intro': DialogueNode(
            id: 'intro',
            textKey: 'intro.text',
            autoAdvance: true,
            autoAdvanceDelay: 0,
            choices: [
              DialogueChoice(
                textKey: '',
                onSelectEvent: const <String, dynamic>{},
                nextNodeId: 'outro',
              ),
            ],
          ),
          'outro': DialogueNode(
            id: 'outro',
            textKey: 'outro.text',
            choices: const [],
          ),
        },
      );

      final compiledTrace = _runScript(compiled, [0]);
      final handTrace = _runScript(handWritten, [0]);

      expect(compiledTrace.shownNodeIds, handTrace.shownNodeIds);
      expect(compiledTrace.ended, handTrace.ended);
      expect(compiledTrace.shownNodeIds, ['intro', 'outro']);
    },
  );

  test('a choice node compiles each entry to a DialogueChoice on its port', () {
    const graph = Graph(
      nodes: [
        GraphNode(
          id: 'ask',
          kind: 'choice',
          params: {
            'textKey': 'ask.text',
            'choices': [
              {'id': 'yes', 'textKey': 'choice.yes'},
              {'id': 'no', 'textKey': 'choice.no'},
            ],
          },
        ),
        GraphNode(id: 'glad', kind: 'say', params: {'textKey': 'glad.text'}),
        GraphNode(id: 'sad', kind: 'say', params: {'textKey': 'sad.text'}),
      ],
      edges: [
        GraphEdge(
          fromNode: 'ask',
          fromPort: 'yes',
          toNode: 'glad',
          toPort: 'in',
        ),
        GraphEdge(fromNode: 'ask', fromPort: 'no', toNode: 'sad', toPort: 'in'),
      ],
      entryNodeId: 'ask',
    );
    final compiled = compileDialogueGraph(graph);

    final ask = compiled.nodes['ask']!;
    expect(ask.choices, hasLength(2));
    expect(ask.choices[0].textKey, 'choice.yes');
    expect(ask.choices[0].nextNodeId, 'glad');
    expect(ask.choices[1].textKey, 'choice.no');
    expect(ask.choices[1].nextNodeId, 'sad');

    final gladTrace = _runScript(compiled, [0]);
    expect(gladTrace.shownNodeIds, ['ask', 'glad']);
    final sadTrace = _runScript(compiled, [1]);
    expect(sadTrace.shownNodeIds, ['ask', 'sad']);
  });

  test('a say node with no outgoing edge ends the dialogue there', () {
    const graph = Graph(
      nodes: [
        GraphNode(id: 'only', kind: 'say', params: {'textKey': 'x'}),
      ],
      entryNodeId: 'only',
    );
    final compiled = compileDialogueGraph(graph);
    expect(compiled.nodes['only']!.choices, isEmpty);
    expect(compiled.nodes['only']!.autoAdvance, isFalse);
  });

  test('a choice entry with no outgoing edge has a null nextNodeId', () {
    const graph = Graph(
      nodes: [
        GraphNode(
          id: 'ask',
          kind: 'choice',
          params: {
            'choices': [
              {'id': 'bye', 'textKey': 'Goodbye'},
            ],
          },
        ),
      ],
      entryNodeId: 'ask',
    );
    final compiled = compileDialogueGraph(graph);
    expect(compiled.nodes['ask']!.choices.single.nextNodeId, isNull);
  });

  group('rejects what it does not support', () {
    test('a missing entry node is a compile error', () {
      const graph = Graph(
        nodes: [GraphNode(id: 'a', kind: 'say')],
      );
      expect(
        () => compileDialogueGraph(graph),
        throwsA(isA<DialogueCompileError>()),
      );
    });

    test('a non-dialogue node kind is a compile error, not a silent skip', () {
      const graph = Graph(
        nodes: [GraphNode(id: 'w', kind: 'wait')],
        entryNodeId: 'w',
      );
      expect(
        () => compileDialogueGraph(graph),
        throwsA(isA<DialogueCompileError>()),
      );
    });
  });
}
