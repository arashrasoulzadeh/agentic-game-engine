import 'package:engine_core/engine_core.dart';
import 'package:engine_schema/engine_schema.dart';

import '../level/level_editor.dart';

/// One component on the selected entity as the inspector shows it: its name,
/// its schema if the engine has one, and its current JSON.
class InspectedComponent {
  final String name;
  final ComponentSchema? schema;
  final Map<String, dynamic> json;

  const InspectedComponent({
    required this.name,
    required this.schema,
    required this.json,
  });
}

/// The rules behind the property inspector, separated from the widget so they
/// can be tested directly. Every change is a [SetComponentFieldCommand] on the
/// editor's history, so it undoes like any other edit, and a value the schema
/// rejects never reaches the document.
class EntityInspector {
  final LevelEditor editor;

  /// Schemas to check edits against. Defaults to every engine component.
  final Map<String, ComponentSchema> schemas;

  EntityInspector(this.editor, {Map<String, ComponentSchema>? schemas})
    : schemas = schemas ?? allComponentSchemas;

  /// The components on the selected entity, in the order the file lists them, or
  /// an empty list when nothing is selected.
  List<InspectedComponent> components() {
    final entity = editor.selected;
    if (entity == null) return const [];
    return [
      for (final entry in entity.components.entries)
        InspectedComponent(
          name: entry.key,
          schema: schemas[entry.key],
          json: entry.value,
        ),
    ];
  }

  /// Sets [field] of [component] on the selected entity to [value], after the
  /// schema checks it. Returns null on success, or the message to show the
  /// designer when the value is rejected (in which case nothing changes).
  String? setField({
    required String component,
    required String field,
    required Object? value,
  }) {
    final entity = editor.selected;
    if (entity == null) {
      return 'Select an entity first.';
    }
    final schema = schemas[component];
    if (schema == null) {
      return '$component has no schema, so its fields cannot be edited here.';
    }
    final fieldSchema = schema.fieldNamed(field);
    if (fieldSchema == null) return '$component has no field "$field".';
    final error = fieldSchema.validate(value);
    if (error != null) return error;

    editor.history.execute(
      SetComponentFieldCommand(
        entity: entity,
        component: component,
        field: field,
        value: value,
      ),
    );
    return null;
  }
}

/// The result of reading a designer's text for a field: the typed value, or the
/// message to show when the text does not fit the field's type.
class ParsedField {
  final Object? value;
  final String? error;

  const ParsedField.ok(this.value) : error = null;
  const ParsedField.invalid(this.error) : value = null;
}

/// Turns the text a designer typed into the value a [FieldSchema] expects. A
/// number field accepts "2" and "2.5"; a vector accepts "3, 4"; a bool and an
/// enum come from their widgets and never reach here as text.
ParsedField parseFieldText(FieldSchema field, String text) {
  final trimmed = text.trim();
  switch (field.type) {
    case FieldType.int:
      final value = int.tryParse(trimmed);
      return value == null
          ? ParsedField.invalid('${field.name} must be a whole number')
          : ParsedField.ok(value);
    case FieldType.double:
      final value = double.tryParse(trimmed);
      return value == null
          ? ParsedField.invalid('${field.name} must be a number')
          : ParsedField.ok(value);
    case FieldType.string:
      return ParsedField.ok(text);
    case FieldType.vector2:
      final parts = trimmed
          .split(',')
          .map((p) => double.tryParse(p.trim()))
          .toList();
      if (parts.length != 2 || parts.any((p) => p == null)) {
        return ParsedField.invalid(
          '${field.name} must be two numbers, like "3, 4"',
        );
      }
      return ParsedField.ok([parts[0], parts[1]]);
    case FieldType.bool:
      if (trimmed == 'true') return const ParsedField.ok(true);
      if (trimmed == 'false') return const ParsedField.ok(false);
      return ParsedField.invalid('${field.name} must be true or false');
    case FieldType.enumeration:
      return field.options.contains(trimmed)
          ? ParsedField.ok(trimmed)
          : ParsedField.invalid(
              '${field.name} must be one of ${field.options.join(', ')}',
            );
    case FieldType.list:
    case FieldType.object:
      return const ParsedField.invalid(
        'lists and objects are edited as JSON, not as text fields',
      );
  }
}
