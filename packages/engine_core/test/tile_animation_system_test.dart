import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('TileAnimationSystem', () {
    test('advances animationElapsed on all TileMaps by dt', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final map1 = world.spawn();
      world.storeOf<Position>().set(map1, Position(0, 0));
      world.storeOf<TileMap>().set(map1, TileMap(
        cols: 10, rows: 10, tileWidth: 10, tileHeight: 10,
        tiles: List.filled(100, 0),
        tileAnimations: {1: [1, 2, 3]},
      ));

      final map2 = world.spawn();
      world.storeOf<Position>().set(map2, Position(0, 0));
      world.storeOf<TileMap>().set(map2, TileMap(
        cols: 10, rows: 10, tileWidth: 10, tileHeight: 10,
        tiles: List.filled(100, 0),
        tileAnimations: {2: [4, 5]},
      ));

      final system = TileAnimationSystem();

      // Initial state
      expect(world.storeOf<TileMap>().get(map1)!.animationElapsed, 0.0);
      expect(world.storeOf<TileMap>().get(map2)!.animationElapsed, 0.0);

      // Advance by 0.016
      system.update(world, 0.016);
      expect(world.storeOf<TileMap>().get(map1)!.animationElapsed, closeTo(0.016, 0.0001));
      expect(world.storeOf<TileMap>().get(map2)!.animationElapsed, closeTo(0.016, 0.0001));

      // Advance by another 0.016
      system.update(world, 0.016);
      expect(world.storeOf<TileMap>().get(map1)!.animationElapsed, closeTo(0.032, 0.0001));
      expect(world.storeOf<TileMap>().get(map2)!.animationElapsed, closeTo(0.032, 0.0001));

      // Different dt
      system.update(world, 0.1);
      expect(world.storeOf<TileMap>().get(map1)!.animationElapsed, closeTo(0.132, 0.0001));
    });

    test('does not crash with no TileMaps', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final system = TileAnimationSystem();
      system.update(world, 0.016); // Should not crash
    });

    test('advances animationElapsed even for TileMaps without tileAnimations', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final map = world.spawn();
      world.storeOf<Position>().set(map, Position(0, 0));
      world.storeOf<TileMap>().set(map, TileMap(
        cols: 10, rows: 10, tileWidth: 10, tileHeight: 10,
        tiles: List.filled(100, 0),
        // No tileAnimations
      ));

      final system = TileAnimationSystem();
      system.update(world, 0.016); // Should not crash

      expect(world.storeOf<TileMap>().get(map)!.animationElapsed, 0.016);
    });

    test('accumulates correctly over multiple updates', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final map = world.spawn();
      world.storeOf<Position>().set(map, Position(0, 0));
      world.storeOf<TileMap>().set(map, TileMap(
        cols: 10, rows: 10, tileWidth: 10, tileHeight: 10,
        tiles: List.filled(100, 0),
        tileAnimations: {1: [1, 2]},
      ));

      final system = TileAnimationSystem();
      const dt = 1.0 / 60.0;

      // Simulate 1 second at 60fps
      for (int i = 0; i < 60; i++) {
        system.update(world, dt);
      }

      expect(world.storeOf<TileMap>().get(map)!.animationElapsed, closeTo(1.0, 0.02));
    });
  });
}