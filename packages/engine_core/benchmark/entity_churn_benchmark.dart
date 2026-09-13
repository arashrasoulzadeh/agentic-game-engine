import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:engine_core/engine_core.dart';

/// Spawn/destroy throughput — relevant to any game that churns entities
/// heavily (projectiles, particles, short-lived pickups). `World.destroy`
/// walks every *registered* component type's store to remove the entity
/// (see `ComponentRegistry.all`/`ComponentRegistration.removeEntity`),
/// so this benchmark's cost scales with how many component types are
/// registered, not just entity count -- worth re-running if that
/// registration list grows meaningfully.
class EntityChurnBenchmark extends BenchmarkBase {
  final int churnCount;
  late World world;

  EntityChurnBenchmark(this.churnCount) : super('EntityChurn(spawn+destroy, n=$churnCount)');

  @override
  void setup() {
    world = World(width: 1000, height: 1000);
    registerCoreComponents(world);
  }

  @override
  void run() {
    for (var i = 0; i < churnCount; i++) {
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<Collider>().set(id, Collider(4));
    }
    // Destroy every entity just spawned this run() so churnCount stays
    // the live population delta per call, not a monotonically growing
    // one across many run() invocations.
    final ids = world.entities.all.toList();
    for (final id in ids) {
      world.destroy(id);
    }
  }
}

void main() {
  for (final n in [100, 1000, 5000]) {
    EntityChurnBenchmark(n).report();
  }
}
