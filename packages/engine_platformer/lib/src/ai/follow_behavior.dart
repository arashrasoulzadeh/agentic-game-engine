import 'package:engine_core/engine_core.dart';

import '../physics/collision_math.dart';
import '../physics/platformer_controller.dart';

/// Chases [target] horizontally at [speed] — the "following" behavior
/// for a ground-based enemy/companion. Only ever touches `Velocity.x`
/// (via [_SetVelocityXAction], not the generic `SetVelocityAction`),
/// leaving `.y` alone so it doesn't fight gravity/jump every tick.
///
/// [maxDistance] (if set) is an aggro range: outside it, the entity
/// stops rather than chasing forever. [stopDistance] avoids jittering
/// back and forth once already alongside the target. [requireLineOfSight]
/// (off by default, so existing behavior is unchanged) makes it stop
/// chasing — same as being out of range — whenever `WorldView.hasLineOfSight`
/// says a wall is between it and [target], so "following" doesn't mean
/// chasing straight through solid geometry.
///
/// [jumpAcrossGaps] (off by default) enables the entity to jump across
/// gaps when chasing. When enabled and the entity is grounded but
/// blocked by a gap (no ground ahead within [jumpCheckAheadDistance]),
/// it will request a jump instead of stopping. Requires the entity to
/// have a `PlatformerController` with `jumpSpeed` > 0. The jump is
/// requested by setting `PlatformerController.jumpRequested = true`,
/// which `JumpSystem` will consume on the same tick (since AI runs
/// before `JumpSystem` in `installPlatformerSystems`).
///
/// [jumpCheckAheadDistance] (default 2 tiles) is how far ahead to check
/// for ground when deciding whether to jump. Should be set based on the
/// entity's jump arc — a larger value means it will jump earlier.
///
/// Note: Even when [jumpAcrossGaps] is false, the entity will still stop
/// at gaps (it won't walk off ledges) — this matches the "avoidLedges"
/// behavior in [PatrolBehavior]. The [jumpAcrossGaps] flag only controls
/// whether it attempts to jump across the gap instead of just stopping.
class FollowBehavior implements Behavior {
  final EntityId target;
  final double speed;
  final double? maxDistance;
  final double stopDistance;
  final bool requireLineOfSight;

  /// Whether to jump across gaps when chasing. Default `false` (existing
  /// behavior unchanged). When `true`, the entity will request a jump
  /// if it's grounded but there's no ground ahead within
  /// [jumpCheckAheadDistance].
  final bool jumpAcrossGaps;

  /// How far ahead (in world px) to check for ground when
  /// checking for gaps. Default is 2 tiles worth of distance.
  /// Should be set based on the entity's jump arc.
  final double jumpCheckAheadDistance;

  FollowBehavior({
    required this.target,
    this.speed = 80,
    this.maxDistance,
    this.stopDistance = 4,
    this.requireLineOfSight = false,
    this.jumpAcrossGaps = false,
    this.jumpCheckAheadDistance = 64,
  });

  @override
  Action decide(WorldView view, EntityId self) {
    final pos = view.component<Position>(self);
    final targetPos = view.component<Position>(target);
    if (pos == null || targetPos == null) {
      return _SetVelocityXAction(self, 0);
    }

    final dx = targetPos.x - pos.x;
    final distance = dx.abs();
    final outOfRange = maxDistance != null && distance > maxDistance!;
    final blocked = requireLineOfSight &&
        !view.hasLineOfSight(pos.x, pos.y, targetPos.x, targetPos.y);
    if (outOfRange || blocked || distance <= stopDistance) {
      return _SetVelocityXAction(self, 0);
    }

    // Always check for gaps ahead (like PatrolBehavior.avoidLedges)
    // Only request a jump if jumpAcrossGaps is true
    return _FollowWithJumpAction(
      self: self,
      target: target,
      vx: dx.sign * speed,
      jumpAcrossGaps: jumpAcrossGaps,
      jumpCheckAheadDistance: jumpCheckAheadDistance,
    );
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

/// Action that follows horizontally, stops at gaps, and optionally requests a jump.
class _FollowWithJumpAction implements Action {
  final EntityId self;
  final EntityId target;
  final double vx;
  final bool jumpAcrossGaps;
  final double jumpCheckAheadDistance;

  _FollowWithJumpAction({
    required this.self,
    required this.target,
    required this.vx,
    required this.jumpAcrossGaps,
    required this.jumpCheckAheadDistance,
  });

  @override
  void apply(World world) {
    // Only check for gaps when on the ground. In the air, continue moving
    // horizontally to clear the gap.
    // Check if entity is on ground using position (since AI runs before
    // collision system, grounded flag may not be set yet).
    final onGround = _isOnGround(world);

    if (onGround) {
      // Check for gap ahead only when on the ground
      final hasGround = _hasGroundAhead(world);

      if (!hasGround) {
        // No ground ahead - stop horizontal movement
        final store = world.storeOf<Velocity>();
        final existing = store.get(self);
        store.set(self, Velocity(0, existing?.y ?? 0));

        // If jumpAcrossGaps is enabled, request a jump.
        // JumpSystem will only fire it if the entity is actually grounded/
        // in coyote time/has air jumps - we just express the intent here.
        if (jumpAcrossGaps) {
          final controller = world.storeOf<PlatformerController>().get(self);
          if (controller != null && controller.jumpSpeed > 0) {
            controller.jumpRequested = true;
          }
        }
        return;
      }
    }

    // Ground ahead or in the air - continue moving horizontally
    final store = world.storeOf<Velocity>();
    final existing = store.get(self);
    store.set(self, Velocity(vx, existing?.y ?? 0));
  }

  /// Checks if there's ground ahead of the entity in the direction of movement.
  bool _hasGroundAhead(World world) {
    final pos = world.storeOf<Position>().get(self);
    final controller = world.storeOf<PlatformerController>().get(self);
    final collider = world.storeOf<Collider>().get(self);
    final targetPos = world.storeOf<Position>().get(target);
    if (pos == null || controller == null || collider == null || targetPos == null) {
      return true; // assume ground exists if we can't check
    }

    final direction = (targetPos.x - pos.x).sign;
    final aheadX = pos.x + direction * jumpCheckAheadDistance;

    // Search for ground in all TileMaps
    final view = WorldView(world);
    for (final mapEntity in view.entitiesWith<TileMap>()) {
      final map = world.storeOf<TileMap>().get(mapEntity)!;
      final origin = world.storeOf<Position>().get(mapEntity) ?? Position(0, 0);

      // Check up to 4 rows down from the entity's feet
      if (hasGroundAhead(
        map,
        origin,
        pos.x,
        pos.y,
        collider.radius,
        aheadX,
        4,
        map.solidTileIds,
        map.oneWayTileIds,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Checks if the entity is on or very close to the ground.
  /// Used instead of controller.grounded because AI runs before
  /// the collision system updates the grounded flag.
  bool _isOnGround(World world) {
    final pos = world.storeOf<Position>().get(self);
    final collider = world.storeOf<Collider>().get(self);
    final vel = world.storeOf<Velocity>().get(self);
    if (pos == null || collider == null) return false;

    final footY = pos.y + collider.radius;

    // Check if foot is within a small threshold of a solid/one-way tile
    for (final mapEntity in WorldView(world).entitiesWith<TileMap>()) {
      final map = world.storeOf<TileMap>().get(mapEntity)!;
      final origin = world.storeOf<Position>().get(mapEntity) ?? Position(0, 0);

      final col = ((pos.x - origin.x) / map.tileWidth).floor();
      if (col < 0 || col >= map.cols) continue;

      // Check row at entity's feet and one row below
      final footRow = ((footY - origin.y) / map.tileHeight).floor();
      for (int row = footRow; row <= footRow + 1 && row < map.rows; row++) {
        if (row < 0) continue;
        final tileId = map.tileAt(col, row);
        if (tileId == 0) continue;
        if (map.solidTileIds.contains(tileId) || map.oneWayTileIds.contains(tileId)) {
          final tileTop = origin.y + row * map.tileHeight;
          // Entity foot is at or just above the tile top
          if ((footY - tileTop).abs() <= 2.0) return true;
        }
      }
    }
    return false;
  }
}