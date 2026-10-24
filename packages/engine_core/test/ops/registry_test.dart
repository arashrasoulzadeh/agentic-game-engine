import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

Operation op(
  String name, {
  OperationKind kind = OperationKind.read,
  OperationScope scope = OperationScope.pure,
  List<Param> params = const [],
  OpHandler? handler,
  bool requiresFlutter = false,
  Deprecation? deprecated,
}) => Operation(
  name: name,
  summary: 's',
  description: 'd',
  kind: kind,
  scope: scope,
  params: params,
  requiresFlutter: requiresFlutter,
  deprecated: deprecated,
  handler: handler ?? (c, a) => OpOutcome.data(a),
);

void main() {
  group('the real registry', () {
    final registry = buildRegistry();

    test('names are unique, well formed and sorted', () {
      final names = [for (final o in registry.all) o.name];
      expect(names.toSet().length, names.length);
      expect(names, [...names]..sort());
      for (final o in registry.all) {
        expect(Operation.namePattern.hasMatch(o.name), isTrue, reason: o.name);
        expect(o.summary.length, lessThanOrEqualTo(100), reason: o.name);
        expect(o.description, isNotEmpty, reason: o.name);
      }
    });

    test(
      'every error code an operation lists exists on the wire and every example is valid for it',
      () async {
        final ctx = OpContext();
        for (final o in registry.all) {
          for (final e in o.errors.keys) {
            expect(ErrorCode.byCode(e.code), e, reason: o.name);
          }
          for (final ex in o.examples) {
            // Examples must at least validate against the operation's own parameters.
            expect(
              () => ParamValidator(
                o.params,
                implicit: o.implicitParams,
              ).coerce(ex.args),
              returnsNormally,
              reason: '${o.name}: ${ex.title}',
            );
          }
        }
        expect(ctx.project, isNull);
      },
    );

    test(
      'read-only operations of pure scope run and match their examples',
      () async {
        final ctx = OpContext();
        for (final o in registry.all.where(
          (o) => o.kind == OperationKind.read && o.scope == OperationScope.pure,
        )) {
          for (final ex in o.examples) {
            final r = await registry.call(o.name, ex.args, ctx);
            expect(r.ok, isTrue, reason: '${o.name}: ${r.error}');
            for (final e in (ex.expect ?? const {}).entries) {
              expect(
                (r.data! as Map)[e.key],
                e.value,
                reason: '${o.name} ${e.key}',
              );
            }
          }
        }
      },
    );

    test('every operation produces a valid JSON-serializable input schema', () {
      for (final o in registry.all) {
        final s = inputSchemaFor(o);
        expect(s['type'], 'object');
        expect(s['additionalProperties'], false);
      }
      expect(allInputSchemas(registry).keys, [
        for (final o in registry.all) o.name,
      ]);
    });
  });

  group('construction', () {
    test('duplicate and malformed names are refused', () {
      expect(
        () => OperationRegistry([op('a.b'), op('a.b')]),
        throwsArgumentError,
      );
      for (final bad in ['nodot', 'A.b', 'a.B', 'a.b.c', 'a.', '.b', '1a.b']) {
        expect(
          () => OperationRegistry([op(bad)]),
          throwsArgumentError,
          reason: bad,
        );
      }
    });
  });

  group('dispatch', () {
    final registry = OperationRegistry([
      op(
        't.echo',
        params: const [Param('x', ParamType.integer, required: true)],
      ),
      op('t.boom', handler: (c, a) => throw StateError('secret detail')),
      op(
        't.fail',
        handler: (c, a) =>
            throw OpError(ErrorCode.notFound, 'gone', hint: 'try again'),
      ),
      op('t.project', scope: OperationScope.project),
      op('t.write', kind: OperationKind.write),
      op(
        't.old',
        deprecated: const Deprecation(
          since: '0.1.0',
          removeIn: '0.3.0',
          replacement: 't.echo',
        ),
      ),
      op('t.flutter', requiresFlutter: true),
    ]);

    test('success envelope carries data and timing', () async {
      final r = await registry.call('t.echo', {'x': '5'}, OpContext());
      expect(r.ok, isTrue);
      expect(r.data, {'x': 5});
      expect(r.toJson(), {
        'ok': true,
        'data': {'x': 5},
        'warnings': <String>[],
        'durationMs': r.durationMs,
      });
    });

    test(
      'unknown operation, bad params and handler errors become error envelopes',
      () async {
        final ctx = OpContext();
        expect(
          (await registry.call('nope.nope', {}, ctx)).error!.code,
          ErrorCode.unknownOperation,
        );
        final bad = await registry.call('t.echo', {}, ctx);
        expect(bad.error!.code, ErrorCode.invalidParams);
        expect(bad.toJson()['error'], containsPair('code', 'invalid_params'));
        final fail = await registry.call('t.fail', {}, ctx);
        expect(fail.error!.toJson(), {
          'code': 'not_found',
          'message': 'gone',
          'hint': 'try again',
        });
      },
    );

    test(
      'an unexpected exception is an internal error that leaks nothing',
      () async {
        final logged = <String>[];
        final r = await registry.call('t.boom', {}, OpContext(log: logged.add));
        expect(r.error!.code, ErrorCode.internal);
        expect(r.error!.message, isNot(contains('secret')));
        expect(logged.single, contains('secret detail'));
      },
    );

    test('a project operation needs a project', () async {
      final r = await registry.call('t.project', {}, OpContext());
      expect(r.error!.code, ErrorCode.notFound);
      expect(r.error!.hint, contains('project.open'));
    });

    test('deprecation adds a warning pointing at the replacement', () async {
      final r = await registry.call('t.old', {}, OpContext());
      expect(r.warnings.single, contains('use t.echo'));
    });

    test(
      'read-only blocks writes before the handler runs; reads still work',
      () async {
        var ran = false;
        final reg = OperationRegistry([
          op(
            't.write',
            kind: OperationKind.write,
            handler: (c, a) {
              ran = true;
              return const OpOutcome.data(null);
            },
          ),
          op('t.read'),
        ]);
        final ctx = OpContext(policy: const Policy(readOnly: true));
        expect(
          (await reg.call('t.write', {}, ctx)).error!.code,
          ErrorCode.readOnly,
        );
        expect(ran, isFalse);
        expect((await reg.call('t.read', {}, ctx)).ok, isTrue);
      },
    );

    test(
      'a write that proposes files is refused without a safety pipeline',
      () async {
        final reg = OperationRegistry([
          op(
            't.w',
            kind: OperationKind.write,
            handler: (c, a) => const OpOutcome.proposal(Proposal([])),
          ),
        ]);
        expect(
          (await reg.call('t.w', {}, OpContext())).error!.code,
          ErrorCode.internal,
        );
      },
    );

    test(
      'writes run one at a time, in call order; reads do not wait',
      () async {
        final order = <String>[];
        final reg = OperationRegistry([
          op(
            't.slow',
            kind: OperationKind.write,
            handler: (c, a) async {
              order.add('slow start');
              await Future<void>.delayed(const Duration(milliseconds: 40));
              order.add('slow end');
              return const OpOutcome.data(null);
            },
          ),
          op(
            't.fast',
            kind: OperationKind.write,
            handler: (c, a) {
              order.add('fast');
              return const OpOutcome.data(null);
            },
          ),
          op(
            't.read',
            handler: (c, a) {
              order.add('read');
              return const OpOutcome.data(null);
            },
          ),
        ]);
        final ctx = OpContext();
        final f = Future.wait([
          reg.call('t.slow', {}, ctx),
          reg.call('t.fast', {}, ctx),
          reg.call('t.read', {}, ctx),
        ]);
        await f;
        expect(order.where((e) => e != 'read'), [
          'slow start',
          'slow end',
          'fast',
        ], reason: 'writes never overlap');
        expect(
          order.indexOf('read'),
          lessThan(order.indexOf('slow end')),
          reason: 'a read does not wait for writes',
        );
      },
    );

    test('a failing write does not block the next one', () async {
      final reg = OperationRegistry([
        op(
          't.bad',
          kind: OperationKind.write,
          handler: (c, a) => throw OpError(ErrorCode.conflict, 'x'),
        ),
        op('t.good', kind: OperationKind.write),
      ]);
      final ctx = OpContext();
      final r = await Future.wait([
        reg.call('t.bad', {}, ctx),
        reg.call('t.good', {}, ctx),
      ]);
      expect(r.map((e) => e.ok), [false, true]);
    });

    test('replacing swaps handlers by name, keeping the rest', () async {
      final r2 = registry.replacing({
        't.flutter': (c, a) => const OpOutcome.data('real'),
      });
      expect((await r2.call('t.flutter', {}, OpContext())).data, 'real');
      expect((await r2.call('t.echo', {'x': 1}, OpContext())).ok, isTrue);
    });
  });

  group('policy', () {
    final reg = OperationRegistry([
      op('level.a'),
      op('level.b'),
      op('release.build', kind: OperationKind.write),
    ]);

    test('deny wins and hides the operation everywhere', () async {
      final ctx = OpContext(
        policy: const Policy(deny: ['release.*', 'level.b']),
      );
      expect([for (final o in reg.visibleTo(ctx)) o.name], ['level.a']);
      expect(
        (await reg.call('level.b', {}, ctx)).error!.code,
        ErrorCode.forbidden,
      );
    });

    test('a non-empty allow list is exclusive', () async {
      final ctx = OpContext(policy: const Policy(allow: ['level.*']));
      expect(
        [for (final o in reg.visibleTo(ctx)) o.name],
        ['level.a', 'level.b'],
      );
      expect(
        (await reg.call('release.build', {}, ctx)).error!.code,
        ErrorCode.forbidden,
      );
    });
  });

  test('every error code has distinct wire names and plausible mappings', () {
    expect(
      {for (final c in ErrorCode.values) c.code}.length,
      ErrorCode.values.length,
    );
    for (final c in ErrorCode.values) {
      expect(c.http, inInclusiveRange(400, 599));
      expect(c.rpc, lessThan(0));
      expect(c.exit, greaterThan(0));
    }
  });
}
