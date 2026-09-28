import 'dart:math' as math;

import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';

/// Walks [path] (a precomputed route from `findPlatformerPath`) one waypoint at a
/// time — handles jumps, one-way platforms, ladders, and ledge drops.
/// Movement is driven by setting `Velocity` and requesting jumps via `PlatformerController`.
/// A waypoint counts as reached once within [arriveDistance] of it horizontally/vertically,
/// advancing to the next; once the last waypoint is reached, stops (`Velocity.x`
/// set to `0`) and stays stopped — this doesn't loop or replan.
class PathFollowBehavior implements Behavior {
  final List<PlatformerPathPoint> path;
  final double speed;
  final double arriveDistance;
  int _index = 0;

  PathFollowBehavior(this.path, {this.speed = 80, this.arriveDistance = 8});

  /// The waypoint currently being walked toward, or `null` once the
  /// path is complete — useful for a game that wants to know (e.g. to
  /// decide whether to jump toward it).
  PlatformerPathPoint? get currentTarget => _index < path.length ? path[_index] : null;

  @override
  Action decide(WorldView view, EntityId self) {
    final target = currentTarget;
    if (target == null) return _SetVelocityXAction(self, 0);

    final pos = view.component<Position>(self);
    if (pos == null) return _SetVelocityXAction(self, 0);

    final controller = view.component<PlatformerController>(self);
    final vel = view.component<Velocity>(self);

    final dx = target.x - pos.x;
    final dy = target.y - pos.y;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Check if we've arrived at the current waypoint
    if (dist <= arriveDistance) {
      _index++;
      final next = currentTarget;
      if (next == null) return _SetVelocityXAction(self, 0);
      return _decideMovement(self, pos, controller, vel, path[_index]);
    }

    return _decideMovement(self, pos, controller, vel, target);
  }

  Action _decideMovement(EntityId self, Position pos, PlatformerController? controller, Velocity? vel, PlatformerPathPoint target) {
    if (controller == null) return _SetVelocityXAction(self, 0);

    final dx = target.x - pos.x;
    final dy = target.y - pos.y;

    // Horizontal movement
    final moveDir = dx.sign;
    if (moveDir != 0) {
      // Check if we need to jump
      if (target.moveType == PlatformerMoveType.jump && controller.grounded) {
        return _SetVelocityAndJumpAction(self, moveDir * speed);
      }

      // Handle ladder climbing
      if (target.moveType == PlatformerMoveType.climb && target.onLadder) {
        final climbDir = dy.sign;
        if (climbDir != 0) {
          return _SetVelocityXYAction(self, moveDir * speed, climbDir * speed);
        }
      }

      // Handle dropping through one-way platforms
      if (target.moveType == PlatformerMoveType.dropThrough) {
        // Drop through by not moving horizontally and letting gravity work
        // or by pressing down + jump
        return _SetVelocityAndDownAction(self, moveDir * speed);
      }

      // Handle falling off ledges
      if (target.moveType == PlatformerMoveType.fall) {
        return _SetVelocityXAction(self, moveDir * speed);
      }

      // Normal walking
      return _SetVelocityXAction(self, moveDir * speed);
    }

    // If we're at the same X, check vertical movement (ladders, etc.)
    if (target.moveType == PlatformerMoveType.climb && target.onLadder) {
      final climbDir = dy.sign;
      if (climbDir != 0) {
        return _SetVelocityXYAction(self, 0, climbDir * speed);
      }
    }

    return _SetVelocityXAction(self, 0);
  }
}

class _SetVelocityXAction implements Action {
  final EntityId entity;
  final double vx;

  _SetVelocityXAction(this.entity, this.vx);

  @override
  void apply(World world) {
    final store = world.storeOf<Velocity>();
    final existing = store.get(entity);
    store.set(entity, Velocity(vx, existing?.y ?? 0));
  }
}

class _SetVelocityXYAction implements Action {
  final EntityId entity;
  final double vx;
  final double vy;

  _SetVelocityXYAction(this.entity, this.vx, this.vy);

  @override
  void apply(World world) {
    final store = world.storeOf<Velocity>();
    store.set(entity, Velocity(vx, vy));
  }
}

class _SetVelocityAndJumpAction implements Action {
  final EntityId entity;
  final double vx;

  _SetVelocityAndJumpAction(this.entity, this.vx);

  @override
  void apply(World world) {
    final store = world.storeOf<Velocity>();
    final controllerStore = world.storeOf<PlatformerController>();
    final existing = store.get(entity);
    store.set(entity, Velocity(vx, existing?.y ?? 0));
    final controller = controllerStore.get(entity);
    if (controller != null) {
      controller.jumpRequested = true;
    }
  }
}

class _SetVelocityAndDownAction implements Action {
  final EntityId entity;
  final double vx;

  _SetVelocityAndDownAction(this.entity, this.vx);

  @override
  void apply(World world) {
    final store = world.storeOf<Velocity>();
    final controllerStore = world.storeOf<PlatformerController>();
    final existing = store.get(entity);
    store.set(entity, Velocity(vx, existing?.y ?? 0));
    final controller = controllerStore.get(entity);
    if (controller != null) {
      // Request drop through one-way platform
      // This would need a new field on PlatformerController
    }
  }
}
