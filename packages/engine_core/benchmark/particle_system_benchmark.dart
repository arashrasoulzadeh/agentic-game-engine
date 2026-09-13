import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:engine_core/engine_core.dart';

/// Steady-state cost of `ParticleSystem` once it's emitting and aging a
/// large, roughly-constant population: [emitterCount] emitters each
/// spawn a few particles/tick (via `rate`) while previously-spawned
/// particles expire at roughly the same pace, so the live particle
/// count stabilizes rather than growing unbounded across the
/// benchmark's many `run()` calls.
class ParticleSystemBenchmark extends BenchmarkBase {
  final int emitterCount;
  late World world;

  ParticleSystemBenchmark(this.emitterCount) : super('ParticleSystem(emitters=$emitterCount)');

  @override
  void setup() {
    world = World(width: 2000, height: 2000);
    registerCoreComponents(world);
    world.addSystem(ParticleSystem(random: Random(1)));
    world.addSystem(MovementSystem());

    for (var i = 0; i < emitterCount; i++) {
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position((i % 50) * 20.0, (i ~/ 50) * 20.0));
      world.storeOf<ParticleEmitter>().set(
            id,
            ParticleEmitter(rate: 20, lifetimeMin: 0.3, lifetimeMax: 0.3),
          );
    }

    // Run a few ticks up front so the live particle population reaches
    // its steady state before measurement starts.
    for (var i = 0; i < 20; i++) {
      world.step(0.016);
    }
  }

  @override
  void run() => world.step(0.016);
}

void main() {
  for (final n in [10, 100, 500]) {
    ParticleSystemBenchmark(n).report();
  }
}
