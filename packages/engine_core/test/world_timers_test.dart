import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() => World(width: 10, height: 10);

void main() {
  test('after fires once, on the step it comes due', () {
    final world = _world();
    var fired = 0;
    final t = world.after(0.35, () => fired++);
    final at = <int>[];
    for (var i = 1; i <= 6; i++) {
      world.step(0.1);
      if (fired > at.length) at.add(i);
    }
    expect(at, [4]);
    expect(fired, 1);
    expect(t.isActive, isFalse);
  });

  test('after(0) fires on the next step', () {
    final world = _world();
    var fired = 0;
    world.after(0, () => fired++);
    expect(fired, 0);
    world.step(0.016);
    expect(fired, 1);
  });

  test('every fires each interval and keeps going', () {
    final world = _world();
    var fired = 0;
    world.every(0.25, () => fired++);
    for (var i = 0; i < 10; i++) {
      world.step(0.1);
    }
    expect(fired, 4, reason: '1.0s of time, 0.25s apart');
  });

  test('a long step fires a repeating timer once per elapsed interval', () {
    final world = _world();
    var fired = 0;
    world.every(0.1, () => fired++);
    world.step(0.5);
    expect(fired, 5);
  });

  test('cancel stops a timer, including from inside its own callback', () {
    final world = _world();
    var a = 0;
    var b = 0;
    final ta = world.every(0.1, () => a++);
    late TimerHandle tb;
    tb = world.every(0.1, () {
      b++;
      if (b == 2) tb.cancel();
    });
    world.step(0.1);
    ta.cancel();
    ta.cancel();
    for (var i = 0; i < 5; i++) {
      world.step(0.1);
    }
    expect(a, 1);
    expect(b, 2);
    expect(tb.isActive, isFalse);
  });

  test('timers due on the same step fire in registration order', () {
    final world = _world();
    final log = <String>[];
    world.after(0.1, () => log.add('first'));
    world.after(0.1, () => log.add('second'));
    world.step(0.1);
    expect(log, ['first', 'second']);
  });

  test('a timer created by a callback starts counting on the next step', () {
    final world = _world();
    final log = <String>[];
    world.after(0.1, () {
      log.add('outer');
      world.after(0, () => log.add('inner'));
    });
    world.step(0.1);
    expect(log, ['outer']);
    world.step(0.1);
    expect(log, ['outer', 'inner']);
  });

  test(
    'timers follow simulated time: a zero-dt step does not advance them',
    () {
      final world = _world();
      var fired = 0;
      world.after(0.1, () => fired++);
      for (var i = 0; i < 10; i++) {
        world.step(0);
      }
      expect(fired, 0);
    },
  );

  test(
    'timers run before systems in the step and leave serialization alone',
    () {
      final world = _world();
      registerCoreComponents(world);
      final log = <String>[];
      world.addSystemFn('sys', (_, _) => log.add('system'));
      world.after(0.1, () => log.add('timer'));
      world.step(0.1);
      expect(log, ['timer', 'system']);
      expect(world.toJson()['entities'], isEmpty);
    },
  );

  test('bad durations are rejected', () {
    final world = _world();
    expect(() => world.after(-1, () {}), throwsArgumentError);
    expect(() => world.every(0, () {}), throwsArgumentError);
  });
}
