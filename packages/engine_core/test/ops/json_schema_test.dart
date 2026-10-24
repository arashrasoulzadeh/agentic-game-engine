import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:engine_schema/engine_schema.dart';
import 'package:test/test.dart';

void main() {
  test('each ParamType maps to its JSON Schema', () {
    expect(paramSchema(const Param('s', ParamType.string, description: 'd')), {
      'type': 'string',
      'description': 'd',
    });
    expect(paramSchema(const Param('p', ParamType.path)), {
      'type': 'string',
      'minLength': 1,
      'description': 'Project-relative path.',
    });
    expect(
      paramSchema(
        const Param('i', ParamType.integer, min: 1, max: 9, defaultValue: 3),
      ),
      {'type': 'integer', 'minimum': 1, 'maximum': 9, 'default': 3},
    );
    expect(paramSchema(const Param('n', ParamType.number))['type'], 'number');
    expect(paramSchema(const Param('b', ParamType.boolean))['type'], 'boolean');
    expect(
      paramSchema(const Param('e', ParamType.enumeration, options: ['a', 'b'])),
      {
        'type': 'string',
        'enum': ['a', 'b'],
      },
    );
    expect(
      paramSchema(
        const Param('a', ParamType.array, items: Param('', ParamType.integer)),
      ),
      {
        'type': 'array',
        'items': {'type': 'integer'},
      },
    );
    expect(
      paramSchema(const Param('o', ParamType.object))['additionalProperties'],
      true,
    );
    expect(paramSchema(const Param('j', ParamType.json)), isEmpty);
  });

  test('an object with known properties lists them and what is required', () {
    final s = paramSchema(
      const Param(
        'o',
        ParamType.object,
        properties: [
          Param('x', ParamType.number, required: true),
          Param('y', ParamType.number),
        ],
      ),
    );
    expect((s['properties']! as Map).keys, ['x', 'y']);
    expect(s['required'], ['x']);
  });

  test(
    'inputSchemaFor adds apply/confirmation to writes only and forbids unknown keys',
    () {
      Operation op(OperationKind k) => Operation(
        name: 'a.b',
        summary: 's',
        description: 'd',
        kind: k,
        scope: OperationScope.pure,
        params: const [Param('x', ParamType.string, required: true)],
        handler: (c, a) => const OpOutcome.data(null),
      );
      final read = inputSchemaFor(op(OperationKind.read));
      expect((read['properties']! as Map).keys, ['x']);
      expect(read['required'], ['x']);
      expect(read['additionalProperties'], false);
      final write = inputSchemaFor(op(OperationKind.write));
      expect((write['properties']! as Map).keys, [
        'x',
        'apply',
        'confirmation',
      ]);
    },
  );

  test('field types map, ranges and optional fields included', () {
    expect(fieldJsonSchema(const FieldSchema('a', FieldType.int, min: 0)), {
      'type': 'integer',
      'minimum': 0,
    });
    expect(fieldJsonSchema(const FieldSchema('v', FieldType.vector2)), {
      'type': 'array',
      'items': {'type': 'number'},
      'minItems': 2,
      'maxItems': 2,
    });
    expect(
      fieldJsonSchema(
        const FieldSchema('n', FieldType.string, optional: true),
      )['type'],
      ['string', 'null'],
    );
    expect(
      fieldJsonSchema(
        const FieldSchema('e', FieldType.enumeration, options: ['x']),
      )['enum'],
      ['x'],
    );
  });

  test(
    'every registered component converts to a schema with its required fields',
    () {
      for (final c in allComponentSchemas.values) {
        final s = componentJsonSchema(c);
        expect((s['properties']! as Map).keys, [
          for (final f in c.fields) f.name,
        ], reason: c.name);
        expect(s['required'], [
          for (final f in c.fields)
            if (f.required) f.name,
        ], reason: c.name);
      }
      expect(allComponentSchemas, isNotEmpty);
      // The default template of each component carries every required field.
      final world = World(width: 1, height: 1);
      expect(world, isNotNull);
      for (final c in allComponentSchemas.values) {
        for (final f in c.fields.where((f) => f.required)) {
          expect(
            c.template.containsKey(f.name),
            isTrue,
            reason: '${c.name}.${f.name}',
          );
        }
      }
    },
  );
}
