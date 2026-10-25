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
}
