import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

int _run(FixedStepper s, List<double> frames) {
  var steps = 0;
  for (final f in frames) {
    steps += s.advance(f, (_) {});
  }
  return steps;
}

void main() {
  test('every callback gets exactly the fixed step', () {
    final s = FixedStepper(1 / 60);
    final seen = <double>[];
    s.advance(0.05, seen.add);
    expect(seen, everyElement(1 / 60));
    expect(seen.length, 3);
  });

  test('the number of steps depends on elapsed time, not on frame rate', () {
    final oneSecond = [
      [for (var i = 0; i < 30; i++) 1 / 30],
      [for (var i = 0; i < 60; i++) 1 / 60],
      [for (var i = 0; i < 144; i++) 1 / 144],
      [for (var i = 0; i < 10; i++) 0.1],
    ];
    for (final frames in oneSecond) {
      expect(_run(FixedStepper(1 / 60, maxStepsPerFrame: 10), frames), 60);
    }
  });

  test('uneven frames still add up and leftover time carries over', () {
    final s = FixedStepper(0.1);
    expect(s.advance(0.04, (_) {}), 0);
    expect(s.leftover, closeTo(0.04, 1e-12));
    expect(s.advance(0.07, (_) {}), 1);
    expect(s.leftover, closeTo(0.01, 1e-9));
  });

  test('alpha is the fraction of the next step already elapsed', () {
    final s = FixedStepper(0.1);
    s.advance(0.025, (_) {});
    expect(s.alpha, closeTo(0.25, 1e-9));
  });

  test('a huge frame is capped and the excess dropped, not replayed', () {
    final s = FixedStepper(0.1, maxStepsPerFrame: 3);
    expect(s.advance(10, (_) {}), 3);
    expect(s.leftover, 0);
    expect(s.advance(0.05, (_) {}), 0, reason: 'no backlog left over');
  });

  test('reset forgets carried time', () {
    final s = FixedStepper(0.1);
    s.advance(0.09, (_) {});
    s.reset();
    expect(s.advance(0.02, (_) {}), 0);
  });

  test('drives a world: same tick count at different frame rates', () {
    World run(List<double> frames) {
      final world = World(width: 10, height: 10);
      final s = FixedStepper(1 / 60, maxStepsPerFrame: 10);
      for (final f in frames) {
        s.advance(f, world.step);
      }
      return world;
    }

    final a = run([for (var i = 0; i < 30; i++) 1 / 30]);
    final b = run([for (var i = 0; i < 120; i++) 1 / 120]);
    expect(a.tick, 30 * 2);
    expect(b.tick, a.tick);
  });

  test('bad arguments are rejected', () {
    expect(() => FixedStepper(0), throwsArgumentError);
    expect(() => FixedStepper(-1), throwsArgumentError);
    expect(() => FixedStepper(0.1, maxStepsPerFrame: 0), throwsArgumentError);
    expect(() => FixedStepper(0.1).advance(-0.1, (_) {}), throwsArgumentError);
  });
}
