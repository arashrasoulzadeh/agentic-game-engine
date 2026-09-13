import 'package:engine_core/engine_core.dart';

import 'health.dart';

/// Emitted by [damageEntity] the tick an entity's `Health.current`
/// first drops to 0 or below — fires exactly once per death (repeated
/// damage against an already-dead entity doesn't re-emit). Listen for
/// it the same way as any other event, e.g.
/// `world.events.on<DeathEvent>((e) => ...)`, to trigger a respawn
/// (see `respawnPlayer`) or remove the entity.
class DeathEvent {
  final EntityId entity;
  DeathEvent(this.entity);
}

/// Applies [amount] damage to [entity]'s `Health`, respecting
/// `isInvincible` (a no-op while invincible — returns `false`) and
/// starting a new invincibility window of [invincibilitySeconds] once
/// the hit lands. Emits [DeathEvent] the moment `current` crosses to
/// zero or below. Returns `true` if damage was actually applied.
///
/// A no-op (returns `false`) if [entity] has no `Health` component —
/// safe to call from a collision handler without checking first.
bool damageEntity(
  World world,
  EntityId entity,
  double amount, {
  double invincibilitySeconds = 0.5,
}) {
  final health = world.storeOf<Health>().get(entity);
  if (health == null || health.isInvincible || health.isDead) return false;

  health.current -= amount;
  health.invincibleSeconds = invincibilitySeconds;
  if (health.isDead) {
    world.events.emit(DeathEvent(entity));
  }
  return true;
}

/// Restores [amount] of `Health.current`, clamped to `max`. A no-op if
/// [entity] has no `Health` component.
void healEntity(World world, EntityId entity, double amount) {
  final health = world.storeOf<Health>().get(entity);
  if (health == null) return;
  health.current = (health.current + amount).clamp(0, health.max);
}

/// Wires up "touching anything in [hazards] deals damage" in one call —
/// the common case (spikes, enemy contact damage) — via
/// `World.onCollisionWithAny` under the hood. For anything more
/// specific (damage only under some condition, different amounts per
/// hazard), call `damageEntity` directly from your own collision
/// listener instead; this helper doesn't try to cover every case.
void dealDamageOnTouch(
  World world,
  Set<EntityId> hazards,
  double amount, {
  double invincibilitySeconds = 0.5,
}) {
  world.onCollisionWithAny(hazards, (self, other) {
    damageEntity(world, other, amount, invincibilitySeconds: invincibilitySeconds);
  });
}
