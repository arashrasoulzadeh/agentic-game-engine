import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('matches the reference mulberry32 sequence (VM/web/JS parity)', () {
    // Values computed with the canonical JavaScript mulberry32 under node.
    final expected = {
      1: [
        0.6270739405881613,
        0.002735721180215478,
        0.5274470399599522,
        0.9810509674716741,
        0.9683778982143849,
      ],
      42: [
        0.6011037519201636,
        0.44829055899754167,
        0.8524657934904099,
        0.6697340414393693,
        0.17481389874592423,
      ],
      0: [
        0.26642920868471265,
        0.0003297457005828619,
        0.2232720274478197,
        0.1462021479383111,
        0.46732782293111086,
      ],
    };
    expected.forEach((seed, values) {
      final r = WorldRandom(seed);
      expect([for (var i = 0; i < 5; i++) r.nextDouble()], values);
    });
  });

  test('the same seed repeats and different seeds differ', () {
    final a = WorldRandom(7);
    final b = WorldRandom(7);
    final c = WorldRandom(8);
    final seqA = [for (var i = 0; i < 20; i++) a.nextInt(1000)];
    expect([for (var i = 0; i < 20; i++) b.nextInt(1000)], seqA);
    expect([for (var i = 0; i < 20; i++) c.nextInt(1000)], isNot(seqA));
  });

  test('restoring state repeats the draws that followed', () {
    final r = WorldRandom(99);
    for (var i = 0; i < 13; i++) {
      r.nextDouble();
    }
    final saved = r.state;
    final first = [for (var i = 0; i < 10; i++) r.nextInt(100)];
    r.state = saved;
    expect([for (var i = 0; i < 10; i++) r.nextInt(100)], first);
  });

  test('doubles stay in [0, 1) and ints in [0, max) and cover the range', () {
    final r = WorldRandom(5);
    for (var i = 0; i < 5000; i++) {
      final d = r.nextDouble();
      expect(d, inInclusiveRange(0, 0.9999999999));
    }
    final seen = <int>{};
    for (var i = 0; i < 2000; i++) {
      final n = r.nextInt(6);
      expect(n, inInclusiveRange(0, 5));
      seen.add(n);
    }
    expect(seen, {0, 1, 2, 3, 4, 5});
  });

  test('roughly fair: a coin lands both ways, mean near one half', () {
    final r = WorldRandom(11);
    var heads = 0;
    var sum = 0.0;
    for (var i = 0; i < 10000; i++) {
      if (r.nextBool()) heads++;
      sum += r.nextDouble();
    }
    expect(heads, inInclusiveRange(4700, 5300));
    expect(sum / 10000, closeTo(0.5, 0.02));
  });

  test('nextInt rejects a non-positive or oversized max', () {
    final r = WorldRandom(1);
    expect(() => r.nextInt(0), throwsRangeError);
    expect(() => r.nextInt(-3), throwsRangeError);
    expect(() => r.nextInt(4294967297), throwsRangeError);
    expect(r.nextInt(1), 0);
  });

  test('nextRange and pick stay in bounds; pick on empty throws', () {
    final r = WorldRandom(3);
    for (var i = 0; i < 500; i++) {
      expect(r.nextRange(-2, 2), inInclusiveRange(-2, 2));
    }
    expect(['a', 'b', 'c'], contains(r.pick(['a', 'b', 'c'])));
    expect(() => r.pick(<int>[]), throwsStateError);
  });

  test('a world is reproducible by default and seedable', () {
    final a = World(width: 1, height: 1);
    final b = World(width: 1, height: 1);
    final c = World(width: 1, height: 1, seed: 123);
    expect(a.random.nextDouble(), b.random.nextDouble());
    expect(a.seed, 0);
    expect(c.seed, 123);
    expect(c.random.nextDouble(), WorldRandom(123).nextDouble());
  });

  test('a snapshot restores the random stream, so a rollback repeats it', () {
    final world = World(width: 10, height: 10, seed: 5);
    registerCoreComponents(world);
    world.random.nextDouble();
    final snap = WorldSnapshot.capture(world);
    final first = [for (var i = 0; i < 5; i++) world.random.nextInt(1000)];
    snap.restoreInto(world);
    expect([for (var i = 0; i < 5; i++) world.random.nextInt(1000)], first);
  });

  test('the random state survives snapshot JSON; snapshots without it leave '
      'the stream alone', () {
    final world = World(width: 10, height: 10, seed: 5);
    registerCoreComponents(world);
    world.random.nextDouble();
    final json = WorldSnapshot.capture(world).toJson();
    expect(json['random'], world.random.state);
    final loaded = WorldSnapshot.fromJson(json);
    expect(loaded.randomState, world.random.state);

    final before = world.random.state;
    WorldSnapshot(0, {}).restoreInto(world);
    expect(world.random.state, before);
  });
}
