// The samples in docs/concepts/performance.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Busy extends System {
  @override
  String get name => 'busy';
  @override
  void update(World world, double dt) {
    var x = 0.0;
    for (var i = 0; i < 20000; i++) {
      x += i * 0.5;
    }
    if (x < 0) throw StateError('unreachable');
  }
}

void main() {
  test('profile a world: per-system timings, step cost and entity count', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    world.profiler = WorldProfiler();
    world.addSystem(_Busy());
    for (var i = 0; i < 50; i++) {
      world.spawn();
    }

    for (var i = 0; i < 10; i++) {
      world.step(1 / 60);
    }

    final profiler = world.profiler!;
    expect(profiler.steps, 10);
    expect(profiler.entityCount, 50);
    expect(profiler.report().single.name, 'busy');
    expect(profiler.report().single.samples, 10);
    expect(profiler.stepMs, greaterThan(0));
    expect(profiler.format(), contains('busy'));
    expect(profiler.format(), startsWith('step '));
    expect(profiler.toJson()['systems'], hasLength(1));
  });

  test('a world without a profiler pays nothing and has nothing to report', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    world.addSystem(_Busy());
    world.step(1 / 60);
    expect(world.profiler, isNull);
  });

  test('reset clears the numbers but keeps profiling', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    world.profiler = WorldProfiler();
    world.addSystem(_Busy());
    world.step(1 / 60);
    world.profiler!.reset();
    expect(world.profiler!.report(), isEmpty);
    world.step(1 / 60);
    expect(world.profiler!.report(), hasLength(1));
  });
}
