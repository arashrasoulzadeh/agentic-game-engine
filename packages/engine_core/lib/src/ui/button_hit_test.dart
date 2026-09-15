import 'button.dart';
import 'button_hit_box.dart';
import '../physics/collider.dart';
import '../physics/position.dart';
import '../ecs/entity.dart';
import '../ecs/world.dart';

/// The topmost (highest entity id, i.e. most-recently-spawned)
/// `Button`-tagged entity whose hit area contains ([worldX], [worldY]),
/// or `null` if none does. "Topmost" mirrors how overlapping UI is
/// usually authored — a button added later is drawn (and should be
/// tappable) above one added earlier at the same spot.
///
/// A `ButtonHitBox` (centered-rectangle test), when present, is
/// checked instead of `Collider` (circle test) — see `ButtonHitBox`'s
/// own doc comment for why a rectangular option exists. A button with
/// neither component is skipped entirely, same as before either
/// existed.
///
/// `EngineView` converts a tap's screen position to world coordinates
/// via `Camera.screenToWorld` and calls this so `Scene.handleTap`
/// implementations never touch a `ComponentStore` directly for the
/// common "which button did they tap" case.
EntityId? hitTestButton(World world, double worldX, double worldY) {
  final buttons = world.storeOf<Button>();
  final positions = world.storeOf<Position>();
  final colliders = world.storeOf<Collider>();
  final hitBoxes = world.storeOf<ButtonHitBox>();

  EntityId? hit;
  for (var i = 0; i < buttons.length; i++) {
    final entity = buttons.entityAt(i);
    final pos = positions.get(entity);
    if (pos == null) continue;

    final dx = worldX - pos.x;
    final dy = worldY - pos.y;

    final hitBox = hitBoxes.get(entity);
    if (hitBox != null) {
      if (dx.abs() <= hitBox.width / 2 && dy.abs() <= hitBox.height / 2) hit = entity;
      continue;
    }

    final collider = colliders.get(entity);
    if (collider == null) continue;
    if (dx * dx + dy * dy <= collider.radius * collider.radius) hit = entity;
  }
  return hit;
}
