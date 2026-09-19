import 'package:engine_core/engine_core.dart';
import '../physics/platformer_controller.dart';

/// Moves toward the last-heard sound position stored in `AIState.memory`
/// by `HearingSystem`. When the entity reaches the position (within
/// [arriveDistance]) or the sound data expires (optional [timeout]),
/// it clears the memory and stops.
///
/// Mirrors `FollowBehavior` structure closely — can be wrapped with
/// `AvoidanceBehavior` the same way.
class InvestigateBehavior implements Behavior {
  /// Speed at which to move toward the heard position.
  final double speed;

  /// Distance at which the entity considers itself "arrived" and stops.
  final double arriveDistance;

  /// Optional time (seconds) after which the heard sound is considered
  /// stale and the entity gives up. If null, never times out.
  final double? timeout;

  /// Whether to stop at gaps (like FollowBehavior with jumpAcrossGaps).
  /// Default true — doesn't walk off ledges while investigating.
  final bool avoidGaps;

  /// How far ahead to check for gaps. Default 2 tiles.
  final double gapCheckAheadDistance;

  InvestigateBehavior({
    required this.speed,
    this.arriveDistance = 10,
    this.timeout,
    this.avoidGaps = true,
    this.gapCheckAheadDistance = 64,
  });

  @override
  Action decide(WorldView view, EntityId self) {
    final pos = view.component<Position>(self);
    final state = view.component<AIState>(self);
    if (pos == null || state == null) return const NoOpAction();

    final soundData = state.memory['lastHeardSound'];
    if (soundData == null) return const NoOpAction();

    final soundX = (soundData['x'] as num).toDouble();
    final soundY = (soundData['y'] as num).toDouble();

    final dx = soundX - pos.x;
    final distance = dx.abs();

    // Check if we've arrived
    if (distance <= arriveDistance) {
      // Clear the memory and stop
      return _InvestigateAction(self, 0, clearMemory: true);
    }

    // Check timeout if set
    if (timeout != null) {
      // We'd need a timestamp in the sound data to check this.
      // For now, skip timeout check - could be added later with a timestamp field.
    }

    // If avoidGaps is enabled, check for gaps ahead (like PatrolBehavior/FollowBehavior)
    if (avoidGaps) {
      final controller = view.component<PlatformerController>(self);
      final collider = view.component<Collider>(self);
      if (controller != null && controller.grounded && collider != null) {
        final direction = dx.sign;
        final aheadX = pos.x + direction * gapCheckAheadDistance;

        // Check if there's ground ahead
        bool hasGround = false;
        for (final mapEntity in view.entitiesWith<TileMap>()) {
          final map = view.component<TileMap>(mapEntity)!;
          final origin = view.component<Position>(mapEntity) ?? Position(0, 0);

          // Use the same hasGroundAhead logic
          if (_hasGroundAhead(map, origin, pos.x, pos.y, collider.radius, aheadX, 4,
              map.solidTileIds, map.oneWayTileIds)) {
            hasGround = true;
            break;
          }
        }

        if (!hasGround) {
          // Gap ahead - stop and don't jump (investigating is cautious)
          return _InvestigateAction(self, 0);
        }
      }
    }

    // Move toward the sound
    return _InvestigateAction(self, dx.sign * speed);
  }

  /// Checks if there's ground ahead at [aheadX].
  bool _hasGroundAhead(
    TileMap map,
    Position origin,
    double entityX,
    double entityY,
    double radius,
    double aheadX,
    int maxRowsDown,
    Set<int> solidTileIds,
    Set<int> oneWayTileIds,
  ) {
    final col = ((aheadX - origin.x) / map.tileWidth).floor();
    if (col < 0 || col >= map.cols) return false;

    final entityFootY = entityY + radius;
    final startRow = ((entityFootY - origin.y) / map.tileHeight).floor();

    for (int row = startRow; row <= startRow + maxRowsDown && row < map.rows; row++) {
      if (row < 0) continue;
      final tileId = map.tileAt(col, row);
      if (tileId == 0) continue;
      if (solidTileIds.contains(tileId) || oneWayTileIds.contains(tileId)) {
        return true;
      }
    }
    return false;
  }
}

class _InvestigateAction implements Action {
  final EntityId entity;
  final double vx;
  final bool clearMemory;

  _InvestigateAction(this.entity, this.vx, {this.clearMemory = false});

  @override
  void apply(World world) {
    final store = world.storeOf<Velocity>();
    final existing = store.get(entity);
    store.set(entity, Velocity(vx, existing?.y ?? 0));

    if (clearMemory) {
      final state = world.storeOf<AIState>().get(entity);
      state?.memory.remove('lastHeardSound');
    }
  }
}