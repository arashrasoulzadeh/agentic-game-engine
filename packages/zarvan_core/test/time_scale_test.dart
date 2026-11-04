import 'package:test/test.dart';
import 'package:zarvan_core/zarvan_core.dart';

class _Probe implements System {
  final seen = <double>[];

  @override
  String get name => 'probe';

  @override
  void update(World world, double dt) => seen.add(dt);
}

class _RealProbe extends _Probe implements RealTimeSystem {
  @override
  String get name => 'realProbe';
}

void main() {
  test('systems receive dt times timeScale; the default is real time', () {
    final world = World(width: 1, height: 1);
    final probe = _Probe();
    world.addSystem(probe);
    world.step(0.1);
    world.timeScale = 0.25;
    world.step(0.1);
    world.timeScale = 2;
    world.step(0.1);
    expect(probe.seen, [0.1, closeTo(0.025, 1e-12), closeTo(0.2, 1e-12)]);
  });

  test('timeScale 0 pauses systems and timers; real-time systems still run', () {
    final world = World(width: 1, height: 1);
    final sim = _Probe();
    final ui = _RealProbe();
    world.addSystem(sim);
    world.addSystem(ui);
    var fired = false;
    world.after(0.5, () => fired = true);
    world.timeScale = 0;
    for (var i = 0; i < 20; i++) {
      world.step(0.1);
    }
    expect(sim.seen.every((d) => d == 0), isTrue);
    expect(ui.seen.every((d) => d == 0.1), isTrue);
    expect(fired, isFalse);
    world.timeScale = 1;
    for (var i = 0; i < 6; i++) {
      world.step(0.1);
    }
    expect(fired, isTrue);
  });

  test('deltaTime inside a step is the scaled one', () {
    final world = World(width: 1, height: 1);
    world.timeScale = 0.5;
    world.step(0.2);
    expect(world.deltaTime, closeTo(0.1, 1e-12));
  });

  test('timeScale rejects negative and NaN values', () {
    final world = World(width: 1, height: 1);
    expect(() => world.timeScale = -1, throwsArgumentError);
    expect(() => world.timeScale = double.nan, throwsArgumentError);
    expect(world.timeScale, 1);
  });

  group('hitStop', () {
    test('freezes simulated time for real seconds, then resumes at the scale', () {
      final world = World(width: 1, height: 1);
      final sim = _Probe();
      world.addSystem(sim);
      world.timeScale = 0.5;
      world.hitStop(0.25);
      expect(world.isHitStopped, isTrue);
      world.step(0.1); // 0.15 left
      world.step(0.1); // 0.05 left
      expect(world.isHitStopped, isTrue);
      world.step(0.1); // ends during this step, which is still frozen
      expect(world.isHitStopped, isFalse);
      world.step(0.1);
      expect(sim.seen, [0, 0, 0, closeTo(0.05, 1e-12)]);
    });

    test('a longer stop wins over a shorter one; a shorter one is ignored', () {
      final world = World(width: 1, height: 1);
      world.hitStop(0.3);
      world.hitStop(0.1);
      world.step(0.2);
      expect(world.isHitStopped, isTrue);
      world.hitStop(0.5);
      world.step(0.4);
      expect(world.isHitStopped, isTrue);
      world.step(0.2);
      expect(world.isHitStopped, isFalse);
    });

    test('events still flush while frozen, so a paused world can react', () {
      final world = World(width: 1, height: 1);
      var got = 0;
      world.events.on<String>((_) => got++);
      world.hitStop(1);
      world.events.emit('x');
      world.step(0.1);
      expect(got, 1);
    });

    test('the tick counter keeps counting real steps', () {
      final world = World(width: 1, height: 1);
      world.timeScale = 0;
      world.step(0.1);
      world.step(0.1);
      expect(world.tick, 2);
    });
  });
}
