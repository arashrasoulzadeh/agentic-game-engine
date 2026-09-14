import 'tile_map.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';

/// Advances every `TileMap.animationElapsed` by `dt`, so
/// `TileMap.currentTileId` can pick the right frame from
/// `TileMap.tileAnimations` when a renderer draws it. Not auto-added by
/// `installPlatformerSystems`/`GameRunner` — a game opts in the same
/// way it opts into `TweenSystem`, only paying for this tick when it
/// actually uses animated tiles.
class TileAnimationSystem implements System {
  @override
  String get name => 'tileAnimation';

  @override
  void update(World world, double dt) {
    final maps = world.storeOf<TileMap>();
    for (var i = 0; i < maps.length; i++) {
      maps.denseAt(i).animationElapsed += dt;
    }
  }
}
