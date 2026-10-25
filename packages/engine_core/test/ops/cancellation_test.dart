import 'dart:async';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('CancellationToken throwIfCancelled raises cancelled', () {
    final t = CancellationToken();
    expect(t.isCancelled, isFalse);
    t.cancel();
    expect(t.isCancelled, isTrue);
    expect(
      () => t.throwIfCancelled(),
      throwsA(
        isA<OpError>().having((e) => e.code, 'code', ErrorCode.cancelled),
      ),
    );
  });

  test('registry.call surfaces cancelled when the token fires mid-handler', () async {
    final s = await Scratch.create();
    final token = CancellationToken();
    // Spin a long simulate so we can cancel from outside.
    final future = s.registry.call(
      'strategy.simulate_turns',
      {
        'json': {
          'entities': [
            {
              'name': 'red',
              'components': {
                'team': {'id': 'red'},
                'gridPosition': {'col': 0, 'row': 0},
                'actionPoints': {'max': 4},
                'unitStats': {'maxHp': 100, 'attack': 1},
              },
            },
            {
              'name': 'blue',
              'components': {
                'team': {'id': 'blue'},
                'gridPosition': {'col': 7, 'row': 7},
                'actionPoints': {'max': 4},
                'unitStats': {'maxHp': 100, 'attack': 1},
              },
            },
          ],
        },
        'turns': 200,
      },
      s.ctx,
      cancellation: token,
    );
    // Give the handler a moment to enter the step loop, then cancel.
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    final r = await future;
    expect(r.ok, isFalse);
    expect(r.error!.code, ErrorCode.cancelled);
  });

  test('OpContext.cancellation is zone-scoped per call', () async {
    final seen = <bool?>[];
    final registry = OperationRegistry([
      Operation(
        name: 'engine.probe_cancel',
        summary: 'test',
        description: 'test',
        kind: OperationKind.read,
        scope: OperationScope.pure,
        handler: (ctx, a) {
          seen.add(ctx.cancellation?.isCancelled);
          return OpOutcome.data({'ok': true});
        },
      ),
    ]);
    final ctx = OpContext(actor: 'test');
    final token = CancellationToken();
    await registry.call('engine.probe_cancel', {}, ctx, cancellation: token);
    await registry.call('engine.probe_cancel', {}, ctx);
    expect(seen, [false, null]);
  });
}
