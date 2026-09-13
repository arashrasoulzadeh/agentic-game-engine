import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:engine_core/engine_core.dart';

/// `WorldView.nearestWithPosition` is a linear scan over every
/// `Position`, documented as "fine at the entity counts a single AI
/// query needs" with no measurement behind that claim — see TODO.md's
/// "To evaluate" entry. This benchmark puts a number on it: [queryCount]
/// AI-driven entities each calling `nearestWithPosition` once per tick
/// (the realistic case — one query per agent, not one query total),
/// against a world with [entityCount] total `Position`s.
class WorldViewNearestBenchmark extends BenchmarkBase {
  final int entityCount;
  final int queryCount;
  late World world;
  late WorldView view;

  WorldViewNearestBenchmark(this.entityCount, this.queryCount)
      : super('nearestWithPosition(entities=$entityCount, queriesPerTick=$queryCount)');

  @override
  void setup() {
    world = World(width: 2000, height: 2000);
    registerCoreComponents(world);
    for (var i = 0; i < entityCount; i++) {
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position((i * 37) % 2000, (i * 53) % 2000));
    }
    view = WorldView(world);
  }

  @override
  void run() {
    for (var q = 0; q < queryCount; q++) {
      view.nearestWithPosition((q * 17) % 2000, (q * 29) % 2000);
    }
  }
}

void main() {
  // Realistic-to-generous AI entity counts per tick, per the doc
  // comment's "fine at the entity counts a single AI query needs" --
  // queryCount == entityCount models every entity being AI-driven and
  // querying once per tick, the worst realistic case for this API.
  for (final n in [50, 200, 1000]) {
    WorldViewNearestBenchmark(n, n).report();
  }
}
