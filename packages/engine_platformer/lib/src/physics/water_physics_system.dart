import 'package:engine_core/engine_core.dart';

import 'platformer_controller.dart';
import 'water_zone.dart';

/// Detects `PlatformerController` entities overlapping a `WaterZone`
/// this tick and applies swim physics — distinct from walk/jump rather
/// than a variant of either: `Velocity.y` is buoyancy-capped instead of
/// governed by normal gravity, and a jump press becomes a repeatable
/// upward stroke instead of a single arc. Runs after `GravitySystem`/
/// `MovementSystem` (so this tick's gravity and position are already
/// applied — the buoyancy cap corrects the *result* of an ordinary
/// gravity tick rather than needing to know `GravitySystem`'s
/// configured strength) and before `JumpSystem` (so a stroke consumes
/// `jumpRequested` before `JumpSystem` would otherwise try to jump with
/// it — harmless either way since `grounded` is false while swimming,
/// but consuming it here keeps the two systems from fighting over the
/// same input flag).
class WaterPhysicsSystem implements System {
  @override
  String get name => 'waterPhysics';

  @override
  void update(World world, double dt) {
    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();
    final colliders = world.storeOf<Collider>();
    final controllers = world.storeOf<PlatformerController>();
    final zones = world.storeOf<WaterZone>();
    if (zones.length == 0) return;

    for (var i = 0; i < controllers.length; i++) {
      final entity = controllers.entityAt(i);
      final controller = controllers.denseAt(i);
      final pos = positions.get(entity);
      final vel = velocities.get(entity);
      final collider = colliders.get(entity);
      controller.inWater = false;
      if (pos == null || vel == null || collider == null) continue;

      for (var j = 0; j < zones.length; j++) {
        final zoneEntity = zones.entityAt(j);
        final zone = zones.denseAt(j);
        final zonePos = positions.get(zoneEntity);
        if (zonePos == null) continue;
        if (!_circleOverlapsRect(pos, collider.radius, zonePos, zone.width, zone.height)) {
          continue;
        }

        controller.inWater = true;
        if (vel.y > zone.maxFallSpeed) vel.y = zone.maxFallSpeed;
        if (controller.jumpRequested) {
          vel.y = -zone.swimUpSpeed;
          controller.jumpRequested = false;
        }
        break; // already submerged -- no need to check further zones this tick
      }
    }
  }

  bool _circleOverlapsRect(
    Position circleCenter,
    double radius,
    Position rectCenter,
    double rectWidth,
    double rectHeight,
  ) {
    final left = rectCenter.x - rectWidth / 2;
    final right = rectCenter.x + rectWidth / 2;
    final top = rectCenter.y - rectHeight / 2;
    final bottom = rectCenter.y + rectHeight / 2;

    final closestX = circleCenter.x.clamp(left, right);
    final closestY = circleCenter.y.clamp(top, bottom);
    final dx = circleCenter.x - closestX;
    final dy = circleCenter.y - closestY;
    return dx * dx + dy * dy <= radius * radius;
  }
}
