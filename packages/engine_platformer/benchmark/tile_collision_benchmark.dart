import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';

/// `TileCollisionSystem` only checks the handful of tiles overlapping
/// each entity's own bounding box (not the whole grid, whatever its
/// size) — this benchmark holds the map size fixed and scales entity
/// count, to isolate that per-entity cost from level size.
class TileCollisionBenchmark extends BenchmarkBase {
  final int entityCount;
  late World world;

  TileCollisionBenchmark(this.entityCount) : super('TileCollisionSystem(n=$entityCount)');

  @override
  void setup() {
    world = World(width: 4000, height: 400);
    registerCoreComponents(world);
    registerPlatformerComponents(world);
    world.addSystem(MovementSystem());
    world.addSystem(GravitySystem());
    world.addSystem(PlatformerSystem());
    world.addSystem(TileCollisionSystem());
    world.addSystem(JumpSystem());

    const cols = 250;
    const rows = 10;
    final tiles = List<int>.generate(cols * rows, (i) => i >= cols * (rows - 1) ? 1 : 0);
    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: cols,
            rows: rows,
            tileWidth: 16,
            tileHeight: 16,
            tiles: tiles,
            solidTileIds: {1},
          ),
        );

    for (var i = 0; i < entityCount; i++) {
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position((i % cols) * 16.0, 100));
      world.storeOf<Velocity>().set(id, Velocity(0, 20));
      world.storeOf<Collider>().set(id, Collider(6));
      world.storeOf<PlatformerController>().set(id, PlatformerController());
    }
  }

  @override
  void run() => world.step(0.016);
}

void main() {
  for (final n in [50, 500, 2000]) {
    TileCollisionBenchmark(n).report();
  }
}
