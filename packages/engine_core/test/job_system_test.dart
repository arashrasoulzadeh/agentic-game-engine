import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Square implements Job<int, int> {
  @override
  int run(int input) => input * input;
}

class _Fails implements Job<int, int> {
  @override
  int run(int input) => throw StateError('bad input $input');
}

class _Slow implements Job<int, int> {
  @override
  int run(int input) {
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(end)) {}
    return input;
  }
}

class _Sum implements Job<List<int>, int> {
  @override
  int run(List<int> input) => input.fold(0, (a, b) => a + b);
}

void main() {
  late JobSystem jobs;

  setUp(() => jobs = JobSystem(workerCount: 2));
  tearDown(() => jobs.shutdown());

  test('a dispatched job runs on a worker and returns its result', () async {
    expect(await jobs.dispatch(_Square(), 7), 49);
  });

  test('start is implicit on the first dispatch and idempotent', () async {
    await jobs.start();
    await jobs.start();
    expect(await jobs.dispatch(_Square(), 3), 9);
  });

  test(
    'concurrent dispatches before the workers are up all wait for the start',
    () async {
      // Regression: the second dispatch used to see "started" and index an empty worker list.
      final results = await Future.wait([
        for (var i = 0; i < 6; i++) jobs.dispatch(_Square(), i),
      ]);
      expect(results, [0, 1, 4, 9, 16, 25]);
    },
  );

  test(
    'a job in flight when the system shuts down fails instead of hanging',
    () async {
      await jobs.start();
      final pending = jobs.dispatch(_Slow(), 1);
      // Let it reach a worker, so it is genuinely in flight.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      jobs.shutdown();
      await expectLater(pending, throwsA(isA<StateError>()));
    },
  );

  test(
    'a batch returns results in input order, spread over the workers',
    () async {
      final out = await jobs.dispatchBatch(_Square(), [1, 2, 3, 4, 5, 6, 7]);
      expect(out, [1, 4, 9, 16, 25, 36, 49]);
    },
  );

  test('structured input and output cross the isolate boundary', () async {
    expect(await jobs.dispatch(_Sum(), [1, 2, 3, 4]), 10);
  });

  test(
    'an error in a job reaches the caller, and the system keeps working',
    () async {
      await expectLater(jobs.dispatch(_Fails(), 5), throwsA(isA<StateError>()));
      expect(await jobs.dispatch(_Square(), 4), 16);
    },
  );

  test('the collision broadphase job finds nearby pairs', () async {
    CollisionEntity e(int id, double x) => CollisionEntity(
      id: id,
      x: x,
      y: 0,
      radius: 4,
      collisionGroup: 1,
      collisionMask: 1,
      pushable: true,
    );
    final entities = [e(1, 0), e(2, 5), e(3, 500)];
    final out = await jobs.dispatch(
      CollisionBroadphaseJob(),
      CollisionBroadphaseInput(
        cellSize: 32,
        worldWidth: 1000,
        entities: entities,
        entityMap: {for (final en in entities) en.id: en},
      ),
    );
    final pairs = {
      for (final p in out.pairs)
        (p.a.id < p.b.id ? (p.a.id, p.b.id) : (p.b.id, p.a.id)),
    };
    expect(pairs, {(1, 2)});
  });

  test(
    'dispatching while a shutdown races the start is a StateError, not a RangeError',
    () async {
      final pending = jobs.dispatch(_Square(), 1);
      jobs.shutdown();
      await expectLater(pending, throwsA(isA<StateError>()));
    },
  );

  test('shutdown can be followed by a fresh start', () async {
    expect(await jobs.dispatch(_Square(), 2), 4);
    jobs.shutdown();
    expect(await jobs.dispatch(_Square(), 3), 9);
  });
}
