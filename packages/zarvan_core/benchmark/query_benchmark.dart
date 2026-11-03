import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:zarvan_core/zarvan_core.dart';

/// Cost of `world.query2` against the hand-written dense loop it replaces, at
/// the same entity counts as `world_step_benchmark`. The query is allowed to
/// be slower (it yields records) but should stay within a small constant
/// factor, since game code will use it in per-tick loops.
World _build(int n) {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  for (var i = 0; i < n; i++) {
    final id = world.spawn();
    world.setComponent(id, Position((i % 100) * 10.0, (i ~/ 100) * 10.0));
    if (i.isEven) world.setComponent(id, Velocity(10, 5));
  }
  return world;
}

class QueryBenchmark extends BenchmarkBase {
  final int n;
  late World world;
  double sink = 0;

  QueryBenchmark(this.n) : super('Query2(Position,Velocity, n=$n)');

  @override
  void setup() => world = _build(n);

  @override
  void run() {
    for (final (_, p, v) in world.query2<Position, Velocity>()) {
      sink += p.x + v.x;
    }
  }
}

class HandLoopBenchmark extends BenchmarkBase {
  final int n;
  late World world;
  double sink = 0;

  HandLoopBenchmark(this.n) : super('HandLoop(Position,Velocity, n=$n)');

  @override
  void setup() => world = _build(n);

  @override
  void run() {
    final ps = world.componentsOf<Position>();
    final vs = world.componentsOf<Velocity>();
    for (var i = 0; i < vs.length; i++) {
      final p = ps.get(vs.entityAt(i));
      if (p != null) sink += p.x + vs.denseAt(i).x;
    }
  }
}

void main() {
  for (final n in [100, 1000, 5000]) {
    HandLoopBenchmark(n).report();
    QueryBenchmark(n).report();
  }
}
