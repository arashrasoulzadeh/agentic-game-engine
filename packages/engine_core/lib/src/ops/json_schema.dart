import 'package:engine_schema/engine_schema.dart';

import 'operation.dart';
import 'param.dart';

/// JSON Schema (draft 2020-12) for one parameter. Used for MCP `inputSchema`, OpenAPI components, CLI help and
/// documentation, so every surface describes inputs identically.
Map<String, Object?> paramSchema(Param p) {
  final out = <String, Object?>{};
  switch (p.type) {
    case ParamType.string:
      out['type'] = 'string';
    case ParamType.path:
      out['type'] = 'string';
      out['minLength'] = 1;
    case ParamType.integer:
      out['type'] = 'integer';
    case ParamType.number:
      out['type'] = 'number';
    case ParamType.boolean:
      out['type'] = 'boolean';
    case ParamType.enumeration:
      out['type'] = 'string';
      out['enum'] = p.options;
    case ParamType.array:
      out['type'] = 'array';
      if (p.items != null) out['items'] = paramSchema(p.items!);
    case ParamType.object:
      out['type'] = 'object';
      if (p.properties.isNotEmpty) {
        out['properties'] = {
          for (final c in p.properties) c.name: paramSchema(c),
        };
        final req = [
          for (final c in p.properties)
            if (c.required) c.name,
        ];
        if (req.isNotEmpty) out['required'] = req;
      }
      out['additionalProperties'] = true;
    case ParamType.json:
      break;
  }
  if (p.min != null) out['minimum'] = p.min;
  if (p.max != null) out['maximum'] = p.max;
  if (p.defaultValue != null) out['default'] = p.defaultValue;
  var description = p.description;
  if (p.type == ParamType.path) {
    description = description.isEmpty
        ? 'Project-relative path.'
        : '$description (project-relative path)';
  }
  if (description.isNotEmpty) out['description'] = description;
  return out;
}

/// The `inputSchema` of [op]: an object with every parameter (plus `apply`/`confirmation` for writes).
Map<String, Object?> inputSchemaFor(Operation op) {
  final all = [...op.params, ...op.implicitParams];
  return {
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
    'properties': {for (final p in all) p.name: paramSchema(p)},
    'required': [
      for (final p in all)
        if (p.required) p.name,
    ],
    'additionalProperties': false,
  };
}

/// JSON Schema for one component field.
Map<String, Object?> fieldJsonSchema(FieldSchema f) {
  final out = <String, Object?>{};
  switch (f.type) {
    case FieldType.int:
      out['type'] = 'integer';
    case FieldType.double:
      out['type'] = 'number';
    case FieldType.bool:
      out['type'] = 'boolean';
    case FieldType.string:
      out['type'] = 'string';
    case FieldType.enumeration:
      out['type'] = 'string';
      out['enum'] = f.options;
    case FieldType.vector2:
      out['type'] = 'array';
      out['items'] = {'type': 'number'};
      out['minItems'] = 2;
      out['maxItems'] = 2;
    case FieldType.list:
      out['type'] = 'array';
    case FieldType.object:
      out['type'] = 'object';
  }
  if (f.min != null) out['minimum'] = f.min;
  if (f.max != null) out['maximum'] = f.max;
  if (f.defaultValue != null) out['default'] = f.defaultValue;
  if (f.optional) {
    final t = out['type'];
    out['type'] = [t, 'null'];
  }
  return out;
}

/// JSON Schema for a whole component (`engine://schemas/components/<name>`).
Map<String, Object?> componentJsonSchema(ComponentSchema c) => {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'title': c.name,
  'type': 'object',
  'properties': {for (final f in c.fields) f.name: fieldJsonSchema(f)},
  'required': [
    for (final f in c.fields)
      if (f.required) f.name,
  ],
  'additionalProperties': true,
};
