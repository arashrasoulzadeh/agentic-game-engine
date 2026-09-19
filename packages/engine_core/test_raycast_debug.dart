import 'package:engine_core/engine_core.dart';

void main() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  
  // Create a TileMap with a wall at col 3
  final mapEntity = world.spawn();
  world.storeOf<Position>().set(mapEntity, Position(0, 0));
  world.storeOf<TileMap>().set(mapEntity, TileMap(
    cols: 10, rows: 5, tileWidth: 40, tileHeight: 40,
    tiles: [
      for (var row = 0; row < 5; row++)
        for (var col = 0; col < 10; col++) (col == 3) ? 1 : 0,
    ],
    solidTileIds: {1},
  ));
  
  final view = WorldView(world);
  
  // Test ray from (100, 100) to (130, 100) - should hit wall at x=120
  final result = view.hasLineOfSight(100, 100, 130, 100);
  print('hasLineOfSight(100,100 -> 130,100): $result'); // Should be false (blocked)
  
  // Test ray from (100, 100) to (70, 100) - should NOT hit wall
  final result2 = view.hasLineOfSight(100, 100, 70, 100);
  print('hasLineOfSight(100,100 -> 70,100): $result2'); // Should be true (not blocked)
}
