import 'package:zarvan_schema/zarvan_schema.dart';
import 'package:test/test.dart';

void main() {
  group('closestMatch', () {
    const names = ['position', 'velocity', 'collider'];

    test('finds a one-letter typo and ignores case', () {
      expect(closestMatch('positon', names), 'position');
      expect(closestMatch('VELOCITY', names), 'velocity');
    });

    test('returns null when nothing is close', () {
      expect(closestMatch('zzz', names), isNull);
      expect(closestMatch('', names), isNull);
    });

    test('didYouMean formats a suffix, or nothing', () {
      expect(didYouMean('colider', names), ' (did you mean "collider"?)');
      expect(didYouMean('zzz', names), '');
    });
  });

  group('schema hints', () {
    const schema = ComponentSchema('thing', [
      FieldSchema('x', FieldType.double, required: true),
      FieldSchema('mode', FieldType.enumeration, options: ['fast', 'slow']),
    ]);

    test('a missing required field shows the line to add', () {
      expect(schema.validate({}), ['x is missing (add "x": 0.0)']);
    });

    test('a mistyped enum value suggests the closest option', () {
      expect(
        schema.validate({'x': 1, 'mode': 'fats'}),
        ['mode must be one of fast, slow (did you mean "fast"?)'],
      );
    });

    test('an enum value nothing like an option gets no suggestion', () {
      expect(
        schema.validate({'x': 1, 'mode': 'warp9'}),
        ['mode must be one of fast, slow'],
      );
    });
  });
}
