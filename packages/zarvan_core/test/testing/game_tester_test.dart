import 'dart:io';

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_core/zarvan_core_testing.dart';
import 'package:test/test.dart';

void main() {
  group('GameTester', () {
    test('tick runs exactly that many steps of dt', () {
      final t = GameTester(dt: 0.1);
      final dts = <double>[];
      t.world.addSystemFn('probe', (_, dt) => dts.add(dt));
      t.tick(3);
      expect(dts, [0.1, 0.1, 0.1]);
      expect(t.world.tick, 3);
      expect(() => t.tick(-1), throwsArgumentError);
    });

    test('advance covers the simulated seconds in whole ticks', () {
      final t = GameTester();
      final ball = t.world.spawnWith([Position(0, 0), Velocity(60, 0)]);
      expect(t.advance(1), 60);
      expect(t.component<Position>(ball).x, closeTo(60, 1));
      expect(() => t.advance(-1), throwsArgumentError);
    });

    test('tickUntil stops as soon as the condition holds', () {
      final t = GameTester(dt: 0.1);
      final ran = t.tickUntil(() => t.world.tick >= 5);
      expect(ran, 5);
      expect(t.world.tick, 5);
    });

    test('tickUntil gives up with a message that includes the world', () {
      final t = GameTester();
      expect(
        () => t.tickUntil(() => false, maxTicks: 3, description: 'the boss'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('the boss'),
              contains('after 3 ticks'),
              contains('World '),
            ),
          ),
        ),
      );
    });

    test('component explains what the entity has instead', () {
      final t = GameTester();
      final id = t.world.spawnAt(1, 1);
      expect(t.component<Position>(id).x, 1);
      expect(
        () => t.component<Velocity>(id),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('has no Velocity'), contains('It has: position')),
          ),
        ),
      );
      t.world.destroy(id);
      expect(
        () => t.component<Position>(id),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'm',
            contains('not alive'),
          ),
        ),
      );
    });

    test('record collects events as the world steps', () {
      final t = GameTester(dt: 0.1);
      t.world.spawnWith([CountdownTimer('x', 0.25)]);
      final fired = t.record<CountdownTimerFired>();
      t.tick(2);
      expect(fired, isEmpty);
      t.tick(1);
      expect(fired.single.name, 'x');
    });

    test('the same seed and inputs give byte-identical snapshot text', () {
      String run() {
        final t = GameTester(seed: 7);
        t.world.spawnWith([Position(0, 0), Velocity(3, 4)]);
        t.world.random.nextDouble();
        t.advance(0.5);
        return t.snapshotText();
      }

      expect(run(), run());
    });

    test('snapshot text is sorted and indented', () {
      final t = GameTester();
      t.world.spawnAt(1, 2);
      final text = t.snapshotText();
      expect(text.indexOf('"entities"'), lessThan(text.indexOf('"random"')));
      expect(text, contains('\n  "'));
      expect(text.indexOf('"seed"'), greaterThan(text.indexOf('"random"')));
    });
  });

  group('expectGolden', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('golden'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('creates a missing golden (and its folders) and passes', () {
      final path = '${dir.path}/a/b/x.txt';
      expectGolden(path, 'hello', env: {});
      expect(File(path).readAsStringSync(), 'hello');
    });

    test('passes on a match and fails on a difference, naming the line', () {
      final path = '${dir.path}/x.txt';
      File(path).writeAsStringSync('one\ntwo\nthree');
      expectGolden(path, 'one\ntwo\nthree', env: {});
      expect(
        () => expectGolden(path, 'one\nTWO\nthree', env: {}),
        throwsA(
          isA<GoldenMismatch>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('line 2'),
              contains('golden: two'),
              contains('actual: TWO'),
              contains('UPDATE_GOLDENS=1'),
            ),
          ),
        ),
      );
    });

    test('a length difference points at the end of the shorter side', () {
      final path = '${dir.path}/x.txt';
      File(path).writeAsStringSync('a\nb');
      expect(
        () => expectGolden(path, 'a\nb\nc', env: {}),
        throwsA(
          isA<GoldenMismatch>().having(
            (e) => e.message,
            'm',
            contains('(end of file)'),
          ),
        ),
      );
    });

    test('UPDATE_GOLDENS=1 overwrites instead of failing', () {
      final path = '${dir.path}/x.txt';
      File(path).writeAsStringSync('old');
      expectGolden(path, 'new', env: {'UPDATE_GOLDENS': '1'});
      expect(File(path).readAsStringSync(), 'new');
    });
  });

  test('a checked-in golden pins a small simulation across refactors', () {
    final t = GameTester(seed: 7);
    t.world.spawnWith([Position(0, 0), Velocity(30, 15), Collider(4)]);
    t.world.spawnWith([Position(40, 20), Collider(4)]);
    t.world.addTag(t.world.entities.all.first, 'ball');
    t.world.random.nextDouble();
    t.advance(1);
    expectGolden('test/golden/small_simulation.json', t.snapshotText());
  });
}
