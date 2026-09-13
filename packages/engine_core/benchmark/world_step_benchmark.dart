import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:engine_core/engine_core.dart';

/// Baseline cost of `World.step()` at a fixed entity count with only the
/// cheapest built-in system (`MovementSystem`) registered — isolates raw
/// per-tick overhead (iterating every ComponentStore once) from any
/// particular system's own cost. Compare against the other benchmarks in
/// this directory to see how much each *additional* system adds on top
/// of this floor.
class WorldStepBenchmark extends BenchmarkBase {
  final int entityCount;
  late World world;

  WorldStepBenchmark(this.entityCount) : super('WorldStep(movement only, n=$entityCount)');

  @override
  void setup() {
    world = World(width: 2000, height: 2000);
    registerCoreComponents(world);
    world.addSystem(MovementSystem());

    for (var i = 0; i < entityCount; i++) {
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position((i % 100) * 10.0, (i ~/ 100) * 10.0));
      world.storeOf<Velocity>().set(id, Velocity(10, 5));
    }
  }

  @override
  void run() => world.step(0.016);
}

void main() {
  for (final n in [100, 1000, 5000]) {
    WorldStepBenchmark(n).report();
  }
}
