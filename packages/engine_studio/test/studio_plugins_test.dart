import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/graph/graph_editor.dart';
import 'package:engine_studio/src/inspector/inspector_panel.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:engine_studio/src/plugins/studio_plugins.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(StudioPlugins.clear);

  group('node kinds', () {
    const shout = NodeKind(
      name: 'shout',
      inputs: [GraphPort('in', PortType.flow)],
      outputs: [GraphPort('out', PortType.flow)],
      paramsSchema: [FieldSchema('volume', FieldType.double)],
    );

    test(
      'a plugin kind joins the graph type\'s registry, only for that type',
      () {
        StudioPlugins.register(
          const StudioPlugin(
            name: 'shouting',
            nodeKinds: {
              GraphType.dialogue: {'shout': shout},
            },
          ),
        );
        expect(
          GraphEditor(type: GraphType.dialogue).registry,
          contains('shout'),
        );
        expect(
          GraphEditor(type: GraphType.dialogue).registry,
          contains('say'),
          reason: 'built-ins stay',
        );
        expect(
          GraphEditor(type: GraphType.behaviorTree).registry,
          isNot(contains('shout')),
        );
      },
    );

    test(
      'the graph validator accepts a plugin kind and still rejects unknown ones',
      () {
        StudioPlugins.register(
          const StudioPlugin(
            name: 'shouting',
            nodeKinds: {
              GraphType.dialogue: {'shout': shout},
            },
          ),
        );
        final registry = GraphEditor(type: GraphType.dialogue).registry;
        Graph graph(String kind) => Graph(
          nodes: [GraphNode(id: 'a', kind: kind)],
          entryNodeId: 'a',
        );
        expect(
          validateGraph(
            graph('shout'),
            registry: registry,
          ).where((i) => i.kind == GraphIssueKind.unknownNodeKind),
          isEmpty,
        );
        expect(
          validateGraph(
            graph('whisper'),
            registry: registry,
          ).where((i) => i.kind == GraphIssueKind.unknownNodeKind),
          isNotEmpty,
        );
      },
    );

    test(
      'registering a plugin again by name replaces it, and unregister removes it',
      () {
        StudioPlugins.register(
          const StudioPlugin(
            name: 'p',
            nodeKinds: {
              GraphType.dialogue: {'shout': shout},
            },
          ),
        );
        StudioPlugins.register(const StudioPlugin(name: 'p'));
        expect(StudioPlugins.all, hasLength(1));
        expect(StudioPlugins.nodeKindsFor(GraphType.dialogue), isEmpty);
        StudioPlugins.unregister('p');
        expect(StudioPlugins.all, isEmpty);
      },
    );
  });

  group('inspector field editors', () {
    testWidgets(
      'a plugin control replaces the default one and edits through the normal path',
      (tester) async {
        final entity = LevelEntity(
          name: 'wall',
          components: {
            'collider': {'radius': 4.0, 'blocksLight': false},
          },
        );
        final editor = LevelEditor(LevelDocument(entities: [entity]))
          ..selected = entity;
        StudioPlugins.register(
          StudioPlugin(
            name: 'sizes',
            fieldEditors: {
              'collider.radius': (context, e) => Wrap(
                children: [
                  for (final r in [4.0, 8.0])
                    TextButton(
                      key: Key('size-$r'),
                      onPressed: () => e.set(r),
                      child: Text('r=$r (now ${e.value})'),
                    ),
                ],
              ),
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InspectorPanel(editor: editor, onChanged: () {}),
            ),
          ),
        );
        expect(
          find.byKey(const Key('field-collider.radius')),
          findsNothing,
          reason: 'the default text field is replaced',
        );
        expect(find.text('r=4.0 (now 4.0)'), findsOneWidget);
        expect(
          find.byKey(const Key('field-collider.blocksLight')),
          findsOneWidget,
          reason: 'other fields are unchanged',
        );

        await tester.tap(find.byKey(const Key('size-8.0')));
        await tester.pump();
        expect(entity.components['collider']!['radius'], 8.0);
        expect(editor.history.canUndo, isTrue);
        editor.history.undo();
        expect(entity.components['collider']!['radius'], 4.0);
      },
    );

    testWidgets('a value the schema rejects is refused, not applied', (
      tester,
    ) async {
      final entity = LevelEntity(
        name: 'wall',
        components: {
          'collider': {'radius': 4.0},
        },
      );
      final editor = LevelEditor(LevelDocument(entities: [entity]))
        ..selected = entity;
      StudioPlugins.register(
        StudioPlugin(
          name: 'bad',
          fieldEditors: {
            'collider.radius': (c, e) => TextButton(
              key: const Key('go'),
              onPressed: () => e.set('not a number'),
              child: const Text('x'),
            ),
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectorPanel(editor: editor, onChanged: () {}),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pump();
      expect(entity.components['collider']!['radius'], 4.0);
    });
  });
}
