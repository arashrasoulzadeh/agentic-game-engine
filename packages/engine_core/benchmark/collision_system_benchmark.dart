import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:engine_core/engine_core.dart';

/// `CollisionSystem`'s cost scales with both entity count and density
/// (entities per spatial-hash cell) — this benchmark packs entities
/// into a fixed-size world so density goes up with `entityCount`,
/// exercising the pair-finding broad-phase under real crowding instead
/// of the sparse case `WorldStepBenchmark` implicitly tests.
class CollisionSystemBenchmark extends BenchmarkBase {
  final int entityCount;
  late World world;

  CollisionSystemBenchmark(this.entityCount)
      : super('CollisionSystem(n=$entityCount, packed)');

  @override
  void setup() {
    world = World(width: 1000, height: 1000);
    registerCoreComponents(world);
    world.addSystem(MovementSystem());
    world.addSystem(CollisionSystem());

    final perRow = (entityCount > 0) ? (entityCount / 10).ceil() : 1;
    for (var i = 0; i < entityCount; i++) {
      final id = world.spawn();
      final x = (i % perRow) * 8.0;
      final y = (i ~/ perRow) * 8.0;
      world.storeOf<Position>().set(id, Position(x, y));
      world.storeOf<Velocity>().set(id, Velocity((i.isEven ? 1 : -1) * 5.0, 0));
      world.storeOf<Collider>().set(id, Collider(4));
    }
  }

  @override
  void run() => world.step(0.016);
}

void main() {
  for (final n in [100, 1000, 5000]) {
    CollisionSystemBenchmark(n).report();
  }
}
