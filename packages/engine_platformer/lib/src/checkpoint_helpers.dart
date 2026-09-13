import 'package:engine_core/engine_core.dart';

import 'combat_helpers.dart';
import 'components/checkpoint.dart';
import 'components/health.dart';
import 'components/last_checkpoint.dart';

/// Registers a collision listener so touching any entity with a
/// `Checkpoint` component records it as [player]'s respawn point (via
/// `LastCheckpoint`) and marks that checkpoint `activated`. Re-touching
/// an already-activated checkpoint is a no-op past the first touch —
/// `activated` is there for a game to show "seen" state, not to gate
/// respawn tracking.
void trackCheckpoints(World world, EntityId player) {
  world.onCollisionInvolving(player, (other) {
    final checkpoint = world.storeOf<Checkpoint>().get(other);
    if (checkpoint == null) return;
    final pos = world.storeOf<Position>().get(other);
    if (pos == null) return;

    checkpoint.activated = true;
    world.storeOf<LastCheckpoint>().set(player, LastCheckpoint(pos.x, pos.y));
  });
}

/// Resets [player] to its `LastCheckpoint` (or [fallbackX]/[fallbackY]
/// if it has none yet — e.g. died before touching a first checkpoint),
/// zeroes `Velocity`, and restores `Health.current` to `max` if present.
/// Call this directly, or wire it to fire automatically on death with
/// `respawnOnDeath`.
void respawnPlayer(
  World world,
  EntityId player, {
  required double fallbackX,
  required double fallbackY,
}) {
  final last = world.storeOf<LastCheckpoint>().get(player);
  final pos = world.storeOf<Position>().get(player);
  if (pos != null) {
    pos.x = last?.x ?? fallbackX;
    pos.y = last?.y ?? fallbackY;
  }

  final vel = world.storeOf<Velocity>().get(player);
  if (vel != null) {
    vel.x = 0;
    vel.y = 0;
  }

  final health = world.storeOf<Health>().get(player);
  if (health != null) {
    health.current = health.max;
    health.invincibleSeconds = 0;
  }
}

/// Wires `respawnPlayer` to fire automatically whenever [player] dies
/// (i.e. `DeathEvent` from `damageEntity` names this entity) — the
/// common case. Skip this and call `respawnPlayer` yourself if you need
/// a delay, a death animation first, or anything else between death and
/// respawn.
void respawnOnDeath(
  World world,
  EntityId player, {
  required double fallbackX,
  required double fallbackY,
}) {
  world.events.on<DeathEvent>((e) {
    if (e.entity != player) return;
    respawnPlayer(world, player, fallbackX: fallbackX, fallbackY: fallbackY);
  });
}
