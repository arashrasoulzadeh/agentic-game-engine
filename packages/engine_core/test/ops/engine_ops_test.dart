import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  final registry = buildRegistry();
  Future<Map<String, Object?>> data(
    String name, [
    Map<String, Object?> args = const {},
    OpContext? ctx,
  ]) async {
    final r = await registry.call(name, args, ctx ?? OpContext());
    expect(r.ok, isTrue, reason: '${r.error}');
    return (r.data is Map ? r.data as Map : {'list': r.data})
        .cast<String, Object?>();
  }

  test('engine.health reports identity and the project state', () async {
    var now = DateTime.utc(2026, 1, 1);
    final ctx = OpContext(clock: () => now, startedAt: now);
    now = now.add(const Duration(seconds: 5));
    final d = await data('engine.health', {}, ctx);
    expect(d['status'], 'ok');
    expect(d['registryVersion'], registry.version);
    expect(d['uptimeMs'], 5000);
    expect(d['project'], {'open': false});
    expect(d['readOnly'], false);
  });

  test(
    'engine.capabilities counts groups, flags unsupported operations and read-only',
    () async {
      final d = await data(
        'engine.capabilities',
        {},
        OpContext(policy: const Policy(readOnly: true)),
      );
      expect((d['groups']! as Map)['engine'], 5);
      expect(d['operationCount'], registry.all.length);
      expect(d['readOnly'], true);
      expect(d['flutter'], false);
      expect(d['unsupported'], isA<List>());
    },
  );

  test(
    'allow/deny hides operations from the catalogue and the count',
    () async {
      final ctx = OpContext(policy: const Policy(deny: ['engine.health']));
      final d = await data('engine.capabilities', {}, ctx);
      expect(d['operationCount'], registry.all.length - 1);
      expect(d['hidden'], 1);
      final list = (await data('engine.operations', {}, ctx))['list']! as List;
      expect(list.any((o) => (o as Map)['name'] == 'engine.health'), isFalse);
    },
  );

  test('engine.operations filters by group and kind', () async {
    final all = (await data('engine.operations'))['list']! as List;
    expect(all.length, registry.all.length);
    final none =
        (await data('engine.operations', {'group': 'nothing'}))['list']!
            as List;
    expect(none, isEmpty);
    final reads =
        (await data('engine.operations', {'kind': 'read'}))['list']! as List;
    expect(reads.every((o) => (o as Map)['kind'] == 'read'), isTrue);
    final bad = await registry.call('engine.operations', {
      'kind': 'danger',
    }, OpContext());
    expect(bad.error!.code, ErrorCode.invalidParams);
  });

  test(
    'engine.operation describes one operation with its input schema and examples',
    () async {
      final d = await data('engine.operation', {'name': 'engine.operations'});
      expect(d['name'], 'engine.operations');
      expect((d['inputSchema']! as Map)['properties'], contains('group'));
      expect((d['examples']! as List), isNotEmpty);
      expect(
        (await registry.call('engine.operation', {
          'name': 'x.y',
        }, OpContext())).error!.code,
        ErrorCode.notFound,
      );
    },
  );

  test('a hidden operation cannot be described either', () async {
    final ctx = OpContext(policy: const Policy(deny: ['engine.health']));
    expect(
      (await registry.call('engine.operation', {
        'name': 'engine.health',
      }, ctx)).error!.code,
      ErrorCode.notFound,
    );
  });
}
