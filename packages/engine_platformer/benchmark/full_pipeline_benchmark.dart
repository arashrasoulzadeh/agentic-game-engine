import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:benchmark_harness/benchmark_harness.dart';

/// A full `installPlatformerSystems` pipeline (player + AI-driven
/// enemies with animation) at increasing enemy counts -- the closest
/// stand-in in this benchmark suite for "what does a real game's frame
/// cost look like," as opposed to the single-system microbenchmarks
/// elsewhere in this directory and in engine_core's.
class FullPipelineBenchmark extends BenchmarkBase {
  final int enemyCount;
  late World world;

  FullPipelineBenchmark(this.enemyCount) : super('FullPlatformerPipeline(enemies=$enemyCount)');

  @override
  void setup() {
    world = World(width: 4000, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);

    final player = spawnPlayer(world, x: 0, y: 100, input: InputState(), maxHealth: 100);

    final behaviors = BehaviorRegistry()
      ..register('patrol', PatrolBehavior(minX: 0, maxX: 3800, speed: 40));

    installPlatformerSystems(world, player: player, behaviors: behaviors);

    for (var i = 0; i < enemyCount; i++) {
      spawnEnemy(
        world,
        x: (i * 15.0) % 3800,
        y: 100,
        behaviorId: 'patrol',
        maxHealth: 10,
      );
    }
  }

  @override
  void run() => world.step(0.016);
}

void main() {
  for (final n in [10, 100, 500]) {
    FullPipelineBenchmark(n).report();
  }
}
