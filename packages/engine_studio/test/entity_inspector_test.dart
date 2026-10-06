import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/inspector/entity_inspector.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:flutter_test/flutter_test.dart';

LevelDocument _level() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'player',
      'components': {
        'position': {'x': 10.0, 'y': 20.0},
        'pushable': {'pushSpeed': 2.5},
        'warpDrive': {'speed': 9},
      },
    },
  ],
});

String _snapshot(LevelDocument doc) => jsonEncode(doc.toJson());

void main() {
  group('components()', () {
    test(
      'lists the selected entity components, with schemas where the engine has them',
      () {
        final editor = LevelEditor(_level())..tap(const Offset(10, 20));
        final components = EntityInspector(editor).components();

        expect(components.map((c) => c.name), [
          'position',
          'pushable',
          'warpDrive',
        ]);
        expect(components[0].schema?.name, 'position');
        expect(
          components[2].schema,
          isNull,
          reason: 'unknown components have no schema',
        );
      },
    );

    test('is empty with no selection', () {
      final editor = LevelEditor(_level());
      expect(EntityInspector(editor).components(), isEmpty);
    });
  });

  group('setField()', () {
    test('a valid value is applied as one undoable command', () {
      final doc = _level();
      final before = _snapshot(doc);
      final editor = LevelEditor(doc)..tap(const Offset(10, 20));
      final inspector = EntityInspector(editor);

      expect(
        inspector.setField(component: 'position', field: 'x', value: 99.0),
        isNull,
      );
      expect(doc.entities.first.components['position']!['x'], 99.0);

      editor.undo();
      expect(_snapshot(doc), before);
    });

    test(
      'a value the schema rejects leaves the document unchanged and says why',
      () {
        final doc = _level();
        final before = _snapshot(doc);
        final editor = LevelEditor(doc)..tap(const Offset(10, 20));

        final error = EntityInspector(
          editor,
        ).setField(component: 'pushable', field: 'pushSpeed', value: -1.0);
        expect(error, 'pushSpeed must be at least 0');
        expect(_snapshot(doc), before);
        expect(
          editor.history.canUndo,
          isFalse,
          reason: 'a rejected edit records nothing',
        );
      },
    );

    test('an undeclared field is rejected with its name', () {
      final editor = LevelEditor(_level())..tap(const Offset(10, 20));
      expect(
        EntityInspector(
          editor,
        ).setField(component: 'position', field: 'z', value: 1.0),
        'position has no field "z".',
      );
    });

    test('a component without a schema cannot be edited here', () {
      final editor = LevelEditor(_level())..tap(const Offset(10, 20));
      expect(
        EntityInspector(
          editor,
        ).setField(component: 'warpDrive', field: 'speed', value: 1),
        'warpDrive has no schema, so its fields cannot be edited here.',
      );
    });

    test('with no selection, it asks for one', () {
      final editor = LevelEditor(_level());
      expect(
        EntityInspector(
          editor,
        ).setField(component: 'position', field: 'x', value: 1.0),
        'Select an entity first.',
      );
    });
  });

  group('parseFieldText()', () {
    FieldSchema field(FieldType type, {List<String> options = const []}) =>
        FieldSchema('f', type, options: options);

    test('reads whole numbers and rejects fractions for int fields', () {
      expect(parseFieldText(field(FieldType.int), ' 42 ').value, 42);
      expect(
        parseFieldText(field(FieldType.int), '2.5').error,
        'f must be a whole number',
      );
    });

    test('reads decimals for double fields and rejects text', () {
      expect(parseFieldText(field(FieldType.double), '2.5').value, 2.5);
      expect(
        parseFieldText(field(FieldType.double), 'fast').error,
        'f must be a number',
      );
    });

    test('reads a two-number vector and rejects anything else', () {
      expect(parseFieldText(field(FieldType.vector2), '3, 4').value, [
        3.0,
        4.0,
      ]);
      expect(parseFieldText(field(FieldType.vector2), '3').error, isNotNull);
    });

    test('accepts only true or false for bool fields', () {
      expect(parseFieldText(field(FieldType.bool), 'true').value, true);
      expect(parseFieldText(field(FieldType.bool), 'yes').error, isNotNull);
    });

    test('accepts only listed options for enum fields', () {
      final facing = field(FieldType.enumeration, options: ['left', 'right']);
      expect(parseFieldText(facing, 'left').value, 'left');
      expect(
        parseFieldText(facing, 'up').error,
        'f must be one of left, right',
      );
    });

    test('keeps strings exactly as typed', () {
      expect(parseFieldText(field(FieldType.string), '  hi  ').value, '  hi  ');
    });

    test('refuses list and object fields, which are edited as JSON', () {
      expect(parseFieldText(field(FieldType.object), '{}').error, isNotNull);
    });
  });
}
