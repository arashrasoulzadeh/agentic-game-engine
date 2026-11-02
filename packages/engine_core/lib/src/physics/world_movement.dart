import 'dart:math' as math;

import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'position.dart';
import 'velocity.dart';

/// Direct-movement helpers for entities that don't use physics velocity
/// (cursors, UI, scripted movers). For anything driven by `MovementSystem`,
/// set [Velocity] instead.
extension WorldMovement on World {
  /// Shifts [entity] by ([dx], [dy]). A no-op for an entity without a
  /// [Position]; returns whether it moved.
  bool move(EntityId entity, double dx, double dy) {
    final p = getComponent<Position>(entity);
    if (p == null) return false;
    p.x += dx;
    p.y += dy;
    return true;
  }

  /// Moves [entity] toward ([x], [y]) by at most [maxDistance], stopping
  /// exactly on the target rather than overshooting. Returns true once it is
  /// there. Pass `speed * dt` as [maxDistance] from a system.
  bool moveToward(EntityId entity, double x, double y, double maxDistance) {
    final p = getComponent<Position>(entity);
    if (p == null) return false;
    final dx = x - p.x, dy = y - p.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= maxDistance || dist == 0) {
      p.x = x;
      p.y = y;
      return true;
    }
    p.x += dx / dist * maxDistance;
    p.y += dy / dist * maxDistance;
    return false;
  }

  /// Gives [entity] a [Velocity] of [speed] toward ([x], [y]) so the movement
  /// system carries it there; zero velocity when already on the point.
  void aimVelocity(EntityId entity, double x, double y, double speed) {
    final p = getComponent<Position>(entity);
    if (p == null) return;
    final dx = x - p.x, dy = y - p.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    final v = getComponent<Velocity>(entity) ?? Velocity(0, 0);
    v.x = dist == 0 ? 0 : dx / dist * speed;
    v.y = dist == 0 ? 0 : dy / dist * speed;
    setComponent(entity, v);
  }
}
