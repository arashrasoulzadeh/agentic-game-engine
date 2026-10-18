import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/graph/graph_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('addNode', () {
    test(
      'adds a node at the given position, and the first one becomes the entry',
      () {
        final editor = GraphEditor();
        final node = editor.addNode('say', const Offset(10, 20));
        expect(editor.nodes.single.id, node.id);
        expect(editor.layout[node.id], const Offset(10, 20));
        expect(editor.entryNodeId, node.id);
      },
    );

    test('ids are unique even for the same kind added twice', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      final b = editor.addNode('say', Offset.zero);
      expect(a.id, isNot(b.id));
    });

    test('a second node does not steal the entry from the first', () {
      final editor = GraphEditor();
      final first = editor.addNode('say', Offset.zero);
      editor.addNode('say', Offset.zero);
      expect(editor.entryNodeId, first.id);
    });
  });

  group('removeNode', () {
    test('removes the node and every edge touching it', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      final b = editor.addNode('say', const Offset(100, 0));
      editor.clickPort(a.id, 'out', isOutput: true);
      editor.clickPort(b.id, 'in', isOutput: false);
      expect(editor.edges, hasLength(1));

      editor.removeNode(a.id);
      expect(editor.nodes.map((n) => n.id), [b.id]);
      expect(editor.edges, isEmpty);
      expect(editor.layout.containsKey(a.id), isFalse);
    });

    test('clears the entry if it pointed at the removed node', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      editor.removeNode(a.id);
      expect(editor.entryNodeId, isNull);
    });

    test('clears the selection if it pointed at the removed node', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      editor.select(a.id);
      editor.removeNode(a.id);
      expect(editor.selectedNodeId, isNull);
    });
  });

  group('clickPort (click-to-connect)', () {
    test('clicking an output then a matching input connects them', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      final b = editor.addNode('say', const Offset(100, 0));

      editor.clickPort(a.id, 'out', isOutput: true);
      expect(editor.armedOutput, (a.id, 'out'));
      editor.clickPort(b.id, 'in', isOutput: false);

      expect(editor.armedOutput, isNull);
      expect(editor.edges.single.fromNode, a.id);
      expect(editor.edges.single.toNode, b.id);
      expect(editor.lastError, isNull);
    });

    test('clicking an input first is rejected, armed stays null', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      editor.clickPort(a.id, 'in', isOutput: false);
      expect(editor.armedOutput, isNull);
      expect(editor.lastError, isNotNull);
    });

    test(
      'clicking a second output instead of an input disarms with an error',
      () {
        final editor = GraphEditor();
        final a = editor.addNode('say', Offset.zero);
        final b = editor.addNode('say', const Offset(100, 0));
        editor.clickPort(a.id, 'out', isOutput: true);
        editor.clickPort(b.id, 'out', isOutput: true);
        expect(editor.armedOutput, isNull);
        expect(editor.edges, isEmpty);
        expect(editor.lastError, isNotNull);
      },
    );

    test('a type mismatch is rejected and nothing is connected', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero); // out: flow
      final b = editor.addNode(
        'branch',
        const Offset(100, 0),
      ); // condition: boolean
      editor.clickPort(a.id, 'out', isOutput: true);
      editor.clickPort(b.id, 'condition', isOutput: false);
      expect(editor.edges, isEmpty);
      expect(editor.lastError, contains('cannot connect'));
    });

    test('connecting to an input that already has an edge replaces it', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      final b = editor.addNode('say', const Offset(100, 0));
      final c = editor.addNode('say', const Offset(200, 0));

      editor.clickPort(a.id, 'out', isOutput: true);
      editor.clickPort(c.id, 'in', isOutput: false);
      expect(editor.edges.single.fromNode, a.id);

      editor.clickPort(b.id, 'out', isOutput: true);
      editor.clickPort(c.id, 'in', isOutput: false);
      expect(editor.edges, hasLength(1));
      expect(editor.edges.single.fromNode, b.id);
    });

    test('cancelArmedPort disarms without an error', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      editor.clickPort(a.id, 'out', isOutput: true);
      editor.cancelArmedPort();
      expect(editor.armedOutput, isNull);
    });
  });

  test('disconnect removes exactly the given edge', () {
    final editor = GraphEditor();
    final a = editor.addNode('say', Offset.zero);
    final b = editor.addNode('say', const Offset(100, 0));
    editor.clickPort(a.id, 'out', isOutput: true);
    editor.clickPort(b.id, 'in', isOutput: false);
    final edge = editor.edges.single;
    editor.disconnect(edge);
    expect(editor.edges, isEmpty);
  });

  test('setParams replaces a node\'s params, keeping its id and kind', () {
    final editor = GraphEditor();
    final a = editor.addNode('say', Offset.zero);
    editor.setParams(a.id, {'textKey': 'hello'});
    expect(editor.nodes.single.id, a.id);
    expect(editor.nodes.single.kind, 'say');
    expect(editor.nodes.single.params['textKey'], 'hello');
  });

  group('validate', () {
    test('a connected linear graph has no issues', () {
      final editor = GraphEditor();
      final a = editor.addNode('say', Offset.zero);
      final b = editor.addNode('say', const Offset(100, 0));
      editor.clickPort(a.id, 'out', isOutput: true);
      editor.clickPort(b.id, 'in', isOutput: false);
      expect(editor.validate(), isEmpty);
    });

    test('an unreachable node is reported', () {
      final editor = GraphEditor();
      editor.addNode('say', Offset.zero);
      editor.addNode('say', const Offset(100, 0));
      expect(
        editor.validate().map((i) => i.kind),
        contains(GraphIssueKind.unreachableNode),
      );
    });
  });

  group('GraphDocument round-trip', () {
    test(
      'a saved and reloaded editor has the same nodes, edges, and layout',
      () {
        final editor = GraphEditor();
        final a = editor.addNode('say', const Offset(5, 6));
        final b = editor.addNode('say', const Offset(50, 60));
        editor.clickPort(a.id, 'out', isOutput: true);
        editor.clickPort(b.id, 'in', isOutput: false);

        final json = editor.document.toJson();
        final reloaded = GraphEditor.fromDocument(GraphDocument.fromJson(json));

        expect(reloaded.nodes.map((n) => n.id), editor.nodes.map((n) => n.id));
        expect(reloaded.edges.length, editor.edges.length);
        expect(reloaded.layout[a.id], const Offset(5, 6));
        expect(reloaded.layout[b.id], const Offset(50, 60));
        expect(reloaded.entryNodeId, editor.entryNodeId);
      },
    );
  });
}
