import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('FieldSchema.validate', () {
    test('accepts a value of the declared type', () {
      expect(const FieldSchema('hp', FieldType.int).validate(5), isNull);
      expect(const FieldSchema('scale', FieldType.double).validate(1), isNull);
      expect(const FieldSchema('on', FieldType.bool).validate(false), isNull);
      expect(const FieldSchema('name', FieldType.string).validate('x'), isNull);
    });

    test('rejects a value of the wrong type and names the field', () {
      expect(
        const FieldSchema('hp', FieldType.int).validate(1.5),
        'hp must be an integer',
      );
      expect(
        const FieldSchema('on', FieldType.bool).validate(1),
        'on must be true or false',
      );
    });

    test('enforces min and max bounds inclusively', () {
      const field = FieldSchema('hp', FieldType.int, min: 0, max: 100);
      expect(field.validate(0), isNull);
      expect(field.validate(100), isNull);
      expect(field.validate(-1), 'hp must be at least 0');
      expect(field.validate(101), 'hp must be at most 100');
    });

    test('enumeration accepts only listed options', () {
      const field = FieldSchema(
        'facing',
        FieldType.enumeration,
        options: ['left', 'right'],
      );
      expect(field.validate('left'), isNull);
      expect(field.validate('up'), 'facing must be one of left, right');
    });

    test('vector2 requires exactly two numbers', () {
      const field = FieldSchema('offset', FieldType.vector2);
      expect(field.validate([1, 2.5]), isNull);
      expect(field.validate([1]), isNotNull);
      expect(field.validate([1, 'a']), isNotNull);
    });
  });

  group('optional, list, and object fields', () {
    test(
      'a missing optional field is valid, a present one is still checked',
      () {
        const field = FieldSchema('tag', FieldType.string, optional: true);
        expect(
          const ComponentSchema('c', [
            FieldSchema('tag', FieldType.string, optional: true),
          ]).validate({}),
          isEmpty,
        );
        expect(field.validate(5), 'tag must be a string');
      },
    );

    test('a null optional field is valid, a null required field is not', () {
      const optional = FieldSchema('data', FieldType.object, optional: true);
      const required = FieldSchema('data', FieldType.object);
      expect(optional.validate(null), isNull);
      expect(required.validate(null), 'data must be an object');
    });

    test('list and object accept only their JSON shape', () {
      expect(
        const FieldSchema('items', FieldType.list).validate([1, 2]),
        isNull,
      );
      expect(
        const FieldSchema('items', FieldType.list).validate({}),
        'items must be a list',
      );
      expect(
        const FieldSchema('data', FieldType.object).validate({'a': 1}),
        isNull,
      );
      expect(
        const FieldSchema('data', FieldType.object).validate([]),
        'data must be an object',
      );
    });
  });

  group('ComponentSchema', () {
    const health = ComponentSchema('health', [
      FieldSchema('current', FieldType.int, min: 0, defaultValue: 100),
      FieldSchema('max', FieldType.int, min: 1, defaultValue: 100),
      FieldSchema('label', FieldType.string),
    ]);

    test('fieldNames preserves declaration order', () {
      expect(health.fieldNames, ['current', 'max', 'label']);
    });

    test('defaults include only fields that declare one', () {
      expect(health.defaults, {'current': 100, 'max': 100});
    });

    test('validate reports every error, not just the first', () {
      final errors = health.validate({'current': -1, 'max': 'many'});
      expect(errors, [
        'current must be at least 0',
        'max must be an integer',
        'label is missing',
      ]);
    });

    test('validate returns empty for a valid object', () {
      expect(
        health.validate({'current': 3, 'max': 10, 'label': 'hero'}),
        isEmpty,
      );
    });
  });
}
