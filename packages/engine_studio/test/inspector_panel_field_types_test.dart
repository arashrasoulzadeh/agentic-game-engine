import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/inspector/inspector_panel.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget coverage for each `FieldType` the inspector renders a different
/// control for (docs/studio/design.md 3.13). `vector2` has no real component using
/// it yet (grep confirms), so it's covered only at the pure-function level in
/// entity_inspector_test.dart's parseFieldText tests; everything here goes
/// through the real widget with a real schema and a real EditCommand.
void main() {
  LevelEditor editorWith(LevelEntity entity) {
    final document = LevelDocument(entities: [entity]);
    final editor = LevelEditor(document);
    editor.selected = entity;
    return editor;
  }

  testWidgets('a bool field renders a Switch, and toggling it edits and undoes', (
    tester,
  ) async {
    final entity = LevelEntity(
      name: 'wall',
      components: {
        'collider': {'radius': 4.0, 'blocksLight': false},
      },
    );
    final editor = editorWith(entity);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(editor: editor, onChanged: () {}),
        ),
      ),
    );

    final switchFinder = find.byKey(const Key('field-collider.blocksLight'));
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, false);

    await tester.tap(switchFinder);
    await tester.pump();

    expect(entity.components['collider']!['blocksLight'], true);
    expect(editor.history.canUndo, isTrue);
    editor.history.undo();
    expect(entity.components['collider']!['blocksLight'], false);
  });

  testWidgets(
    'an enumeration field renders a DropdownButton, and picking an option edits it',
    (tester) async {
      final entity = LevelEntity(
        name: 'emitter',
        components: {
          'particleEmitter': {
            'lifetime': 1.0,
            'emissionShape': 'point',
          },
        },
      );
      final editor = editorWith(entity);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectorPanel(editor: editor, onChanged: () {}),
          ),
        ),
      );

      final dropdownFinder = find.byKey(
        const Key('field-particleEmitter.emissionShape'),
      );
      expect(dropdownFinder, findsOneWidget);
      final dropdown = tester.widget<DropdownButton<String>>(dropdownFinder);
      expect(dropdown.value, 'point');

      // Driven directly rather than through the real overlay menu: the
      // dropdown's popup renders outside the test surface's small default
      // viewport, which flutter_test can't hit-test regardless of the
      // widget's own correctness -- this still exercises the exact callback
      // a real tap-then-select would invoke.
      dropdown.onChanged!('circle');
      await tester.pump();

      expect(
        entity.components['particleEmitter']!['emissionShape'],
        'circle',
      );
      expect(editor.history.canUndo, isTrue);
    },
  );

  testWidgets(
    'a component the engine has no schema for is shown as read-only JSON',
    (tester) async {
      final entity = LevelEntity(
        name: 'mystery',
        components: {
          'notARealComponent': {'whatever': 1},
        },
      );
      final editor = editorWith(entity);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectorPanel(editor: editor, onChanged: () {}),
          ),
        ),
      );

      expect(
        find.byKey(const Key('field-notARealComponent.whatever')),
        findsNothing,
        reason: 'there is no schema to generate a field control from',
      );
      expect(find.textContaining('No schema'), findsOneWidget);
      expect(find.text('{"whatever":1}'), findsOneWidget);
    },
  );

  testWidgets('a list/object field is shown read-only, not an editable control', (
    tester,
  ) async {
    final entity = LevelEntity(
      name: 'player',
      components: {
        'inventory': {'items': <String, dynamic>{'sword': 1}},
      },
    );
    final editor = editorWith(entity);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(editor: editor, onChanged: () {}),
        ),
      ),
    );

    final fieldFinder = find.byKey(const Key('field-inventory.items'));
    expect(fieldFinder, findsOneWidget);
    expect(tester.widget(fieldFinder), isA<SelectableText>());
  });
}
