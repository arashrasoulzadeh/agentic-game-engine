import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

Map<String, Object?> coerce(
  List<Param> params,
  Map<String, Object?> raw, {
  List<Param> implicit = const [],
}) => ParamValidator(params, implicit: implicit).coerce(raw);

List<String> problems(List<Param> params, Map<String, Object?> raw) {
  try {
    coerce(params, raw);
  } on OpError catch (e) {
    expect(e.code, ErrorCode.invalidParams);
    return (e.details!['problems'] as List).cast<String>();
  }
  fail('expected invalid_params');
}

void main() {
  group('coercion (CLI strings become typed values)', () {
    test('integers, numbers and booleans from strings', () {
      final r = coerce(
        const [
          Param('n', ParamType.integer),
          Param('x', ParamType.number),
          Param('b', ParamType.boolean),
        ],
        {'n': ' 42 ', 'x': '1.5', 'b': 'true'},
      );
      expect(r, {'n': 42, 'x': 1.5, 'b': true});
    });

    test('a whole double is an integer, a fractional one is not', () {
      expect(coerce(const [Param('n', ParamType.integer)], {'n': 3.0}), {
        'n': 3,
      });
      expect(problems(const [Param('n', ParamType.integer)], {'n': 3.5}), [
        '"n" must be an integer',
      ]);
    });

    test('defaults fill in; null counts as absent', () {
      final r = coerce(
        const [
          Param('a', ParamType.integer, defaultValue: 7),
          Param('b', ParamType.string),
        ],
        {'b': null},
      );
      expect(r, {'a': 7});
    });

    test('arrays coerce their items, objects and json pass through', () {
      final r = coerce(
        const [
          Param('xs', ParamType.array, items: Param('', ParamType.integer)),
          Param('o', ParamType.object),
          Param('j', ParamType.json),
        ],
        {
          'xs': ['1', 2],
          'o': {'k': 1},
          'j': [1, 'a'],
        },
      );
      expect(r['xs'], [1, 2]);
      expect(r['o'], {'k': 1});
      expect(r['j'], [1, 'a']);
    });
  });

  group('problems are collected, not thrown one at a time', () {
    test('required, unknown, type, range, enum and empty path', () {
      final ps = problems(
        const [
          Param('need', ParamType.string, required: true),
          Param('n', ParamType.integer, min: 1, max: 5),
          Param('e', ParamType.enumeration, options: ['a', 'b']),
          Param('p', ParamType.path),
        ],
        {'n': 9, 'e': 'c', 'p': '', 'typo': 1},
      );
      expect(
        ps,
        containsAll([
          '"need" is required',
          '"n" must be at most 5',
          '"e" must be one of: a, b',
          '"p" must not be empty',
        ]),
      );
      expect(ps.any((p) => p.startsWith('unknown parameter "typo"')), isTrue);
    });

    test('a single problem is the message itself', () {
      try {
        coerce(const [Param('n', ParamType.integer, required: true)], {});
        fail('should throw');
      } on OpError catch (e) {
        expect(e.message, '"n" is required');
      }
    });

    test('wrong shapes', () {
      expect(problems(const [Param('b', ParamType.boolean)], {'b': 'yes'}), [
        '"b" must be true or false',
      ]);
      expect(problems(const [Param('xs', ParamType.array)], {'xs': 'a'}), [
        '"xs" must be a list',
      ]);
      expect(problems(const [Param('o', ParamType.object)], {'o': []}), [
        '"o" must be an object',
      ]);
      expect(
        problems(
          const [
            Param('xs', ParamType.array, items: Param('', ParamType.integer)),
          ],
          {
            'xs': [1, 'x'],
          },
        ),
        ['"xs[1]" must be an integer'],
      );
    });
  });

  test('implicit parameters are accepted next to the declared ones', () {
    final r = coerce(
      const [Param('a', ParamType.string)],
      {'a': 'x', 'apply': 'false'},
      implicit: const [
        Param('apply', ParamType.boolean),
        Param('confirmation', ParamType.string),
      ],
    );
    expect(r, {'a': 'x', 'apply': false});
  });

  group('wrong JSON types', () {
    test(
      'a number where a string is wanted, a string where a number is wanted',
      () {
        expect(problems(const [Param('s', ParamType.string)], {'s': 5}), [
          '"s" must be a string',
        ]);
        expect(problems(const [Param('n', ParamType.number)], {'n': 'abc'}), [
          '"n" must be a number',
        ]);
      },
    );

    test('an untyped array is kept as given', () {
      final r = coerce(
        const [Param('xs', ParamType.array)],
        {
          'xs': [1, 'a', null],
        },
      );
      expect(r['xs'], [1, 'a', null]);
    });
  });

  test('errors print their code and message', () {
    expect(
      OpError(ErrorCode.notFound, 'nope').toString(),
      'OpError(not_found): nope',
    );
  });

  test(
    'a deprecated operation says what replaced it, and a handler can be swapped',
    () async {
      final op = Operation(
        name: 'old.thing',
        summary: 'Old.',
        description: 'Old.',
        kind: OperationKind.read,
        scope: OperationScope.pure,
        deprecated: const Deprecation(
          since: '0.1.0',
          removeIn: '0.3.0',
          replacement: 'new.thing',
        ),
        handler: (ctx, a) => const OpOutcome.data(1),
      );
      final detail = operationDetailJson(op);
      expect(detail['deprecation'], {
        'since': '0.1.0',
        'removeIn': '0.3.0',
        'replacement': 'new.thing',
      });
      final swapped = op.copyWith(handler: (ctx, a) => const OpOutcome.data(2));
      final r = await OperationRegistry([
        swapped,
      ]).call('old.thing', {}, OpContext());
      expect(r.data, 2);
      expect(r.warnings.join(), contains('deprecated'));
      const spec = ResultSpec.any();
      expect(spec.schema, isEmpty);
    },
  );
}
