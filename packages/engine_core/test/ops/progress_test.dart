import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  test('reportProgress reaches a Zone-scoped sink from registry.call', () async {
    final seen = <Map<String, Object?>>[];
    final registry = OperationRegistry([
      Operation(
        name: 'engine.probe_progress',
        summary: 'test',
        description: 'test',
        kind: OperationKind.read,
        scope: OperationScope.pure,
        handler: (ctx, a) {
          ctx.reportProgress(progress: 1, total: 2, message: 'halfway');
          return OpOutcome.data({'ok': true});
        },
      ),
    ]);
    await registry.call(
      'engine.probe_progress',
      {},
      OpContext(actor: 'test'),
      onProgress: seen.add,
    );
    expect(seen, [
      {'progress': 1, 'total': 2, 'message': 'halfway'},
    ]);
  });

  test('world.step reports progress across ticks', () async {
    final seen = <Map<String, Object?>>[];
    final registry = buildRegistry();
    final ctx = OpContext(actor: 'test', onProgress: seen.add);
    final built = await registry.call('world.build', {
      'json': {
        'entities': [
          {
            'name': 'p',
            'components': {
              'position': {'x': 0, 'y': 0},
            },
          },
        ],
      },
    }, ctx);
    expect(built.ok, isTrue, reason: '${built.error}');
    final id = (built.data! as Map)['worldId'];
    final stepped = await registry.call('world.step', {
      'worldId': id,
      'ticks': 3,
    }, ctx);
    expect(stepped.ok, isTrue, reason: '${stepped.error}');
    expect(seen, isNotEmpty);
    expect(seen.first['total'], 3);
  });
}
