import 'package:engine_schema/engine_schema.dart';

import '../../content/level_document.dart';
import '../../validation/level_validator.dart';
import '../json_schema.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';

ComponentSchema _component(String name) =>
    allComponentSchemas[name] ??
    (throw OpError(
      ErrorCode.notFound,
      'No component named "$name".',
      hint: 'List them with schema.components.',
    ));

Map<String, Object?> _fieldJson(FieldSchema f) => {
  'name': f.name,
  'type': f.type.name,
  'required': f.required,
  'optional': f.optional,
  if (f.min != null) 'min': f.min,
  if (f.max != null) 'max': f.max,
  if (f.options.isNotEmpty) 'options': f.options,
  if (f.defaultValue != null) 'default': f.defaultValue,
};

/// `schema.*`: what components exist and what their fields accept, so a client can build valid data first time.
List<Operation> schemaOperations() => [
  Operation(
    name: 'schema.components',
    summary: 'List every component the engine knows, with its field count.',
    description:
        'Names usable in `level.add_entity` and `level.set_field`. `filter` keeps names containing that text.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param(
        'filter',
        ParamType.string,
        description: 'Case-insensitive substring of the name.',
      ),
    ],
    handler: (ctx, a) {
      final f = (a['filter'] as String?)?.toLowerCase();
      return OpOutcome.data([
        for (final e
            in (allComponentSchemas.entries.toList()
              ..sort((x, y) => x.key.compareTo(y.key))))
          if (f == null || e.key.toLowerCase().contains(f))
            {'name': e.key, 'fieldCount': e.value.fields.length},
      ]);
    },
    examples: const [
      Example('Idle components', {'filter': 'generator'}, expect: {}),
    ],
  ),
  Operation(
    name: 'schema.component',
    summary:
        'Describe one component: fields, types, ranges, defaults and its JSON Schema.',
    description:
        'Includes the default template, which is exactly what `level.add_entity` starts a component with.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('name', ParamType.string, required: true, positional: true),
    ],
    errors: {ErrorCode.notFound: 'No component has that name.'},
    handler: (ctx, a) {
      final c = _component(a['name']! as String);
      return OpOutcome.data({
        'name': c.name,
        'fields': [for (final f in c.fields) _fieldJson(f)],
        'template': c.template,
        'jsonSchema': componentJsonSchema(c),
      });
    },
    examples: const [
      Example('Position', {'name': 'position'}),
    ],
  ),
  Operation(
    name: 'schema.template',
    summary: 'The default JSON of a component (every field at its default).',
    description: 'Start from this when building a component by hand.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('name', ParamType.string, required: true, positional: true),
    ],
    handler: (ctx, a) =>
        OpOutcome.data(_component(a['name']! as String).template),
    examples: const [
      Example('Position', {'name': 'position'}, expect: {'x': 0.0}),
    ],
  ),
  Operation(
    name: 'schema.validate_component',
    summary:
        'Check one component value against its schema without touching any file.',
    description:
        'Runs the same validator as level validation on a one-entity level, so the answers agree with `level.validate`.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('name', ParamType.string, required: true, positional: true),
      Param('value', ParamType.json, required: true),
    ],
    handler: (ctx, a) {
      final name = a['name']! as String;
      _component(name);
      final value = a['value'];
      if (value is! Map)
        throw OpError(
          ErrorCode.invalidParams,
          '"value" must be a JSON object.',
        );
      final doc = LevelDocument.fromJson({
        'entities': [
          {
            'name': 'probe',
            'components': {name: value},
          },
        ],
      });
      final issues = LevelValidator.forSchemas(
        allComponentSchemas,
      ).validate(doc);
      String strip(Object i) => i.toString().replaceFirst('probe.$name: ', '');
      return OpOutcome.data({
        'ok': !issues.any((i) => i.severity == IssueSeverity.error),
        'errors': [
          for (final i in issues)
            if (i.severity == IssueSeverity.error) strip(i),
        ],
        'warnings': [
          for (final i in issues)
            if (i.severity != IssueSeverity.error) strip(i),
        ],
      });
    },
    examples: const [
      Example(
        'Valid',
        {
          'name': 'position',
          'value': {'x': 1, 'y': 2},
        },
        expect: {'ok': true},
      ),
    ],
  ),
];
