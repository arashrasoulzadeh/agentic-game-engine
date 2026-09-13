import 'button.dart';
import '../physics/collider.dart';
import '../physics/position.dart';
import '../ecs/entity.dart';
import '../ecs/world.dart';

/// The topmost (highest entity id, i.e. most-recently-spawned)
/// `Button`-tagged entity whose `Collider` circle contains
/// ([worldX], [worldY]), or `null` if none does. "Topmost" mirrors how
/// overlapping UI is usually authored — a button added later is drawn
/// (and should be tappable) above one added earlier at the same spot.
///
/// `EngineView` converts a tap's screen position to world coordinates
/// via `Camera.screenToWorld` and calls this so `Scene.handleTap`
/// implementations never touch a `ComponentStore` directly for the
/// common "which button did they tap" case.
EntityId? hitTestButton(World world, double worldX, double worldY) {
  final buttons = world.storeOf<Button>();
  final positions = world.storeOf<Position>();
  final colliders = world.storeOf<Collider>();

  EntityId? hit;
  for (var i = 0; i < buttons.length; i++) {
    final entity = buttons.entityAt(i);
    final pos = positions.get(entity);
    final collider = colliders.get(entity);
    if (pos == null || collider == null) continue;

    final dx = worldX - pos.x;
    final dy = worldY - pos.y;
    if (dx * dx + dy * dy <= collider.radius * collider.radius) {
      hit = entity;
    }
  }
  return hit;
}
