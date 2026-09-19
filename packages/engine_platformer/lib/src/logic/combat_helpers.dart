import 'dart:math';

import 'package:engine_core/engine_core.dart';

import '../physics/platformer_controller.dart';
import 'health.dart';

/// Emitted by [damageEntity] every time it actually applies damage —
/// regardless of whether the hit was lethal (see [DeathEvent] for
/// that specific case, which fires *in addition to* this one on a
/// killing blow, not instead of it). The generic "something just got
/// hit" signal a game reacts to for anything that cares about damage
/// itself rather than death specifically: a blood/spark particle
/// burst, a hit-flash tint, a floating damage number, a screen shake,
/// a sound effect. Carries [amount] and [source] (the attacker, if
/// [damageEntity] was given one) so a listener doesn't have to
/// re-derive them.
class DamageEvent {
  final EntityId entity;
  final double amount;
  final EntityId? source;
  DamageEvent(this.entity, this.amount, {this.source});
}

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
/// the hit lands. Emits [DamageEvent] every time it actually applies
/// damage, plus [DeathEvent] the moment `current` crosses to zero or
/// below (both fire on a killing blow — [DamageEvent] first). Returns
/// `true` if damage was actually applied.
///
/// A no-op (returns `false`) if [entity] has no `Health` component —
/// safe to call from a collision handler without checking first.
///
/// [knockbackSpeed] (`0` default — disabled) pushes [entity] away from
/// [source] on a hit: both need a `Position` and [entity] needs a
/// `Velocity` for this to do anything, and a zero-distance pair (same
/// position) is skipped rather than dividing by zero. [hitstunSeconds]
/// (`0` default — disabled) sets `PlatformerController.hitstunSeconds`
/// on [entity] if it has one, freezing `PlatformerInputSystem`'s input
/// handling for that entity until it counts down — a no-op for an
/// entity with no `PlatformerController` (e.g. a flying/AI-only
/// enemy), same "harmless if the component isn't there" pattern the
/// rest of this package uses.
bool damageEntity(
  World world,
  EntityId entity,
  double amount, {
  double invincibilitySeconds = 0.5,
  EntityId? source,
  double knockbackSpeed = 0,
  double hitstunSeconds = 0,
}) {
  final health = world.storeOf<Health>().get(entity);
  if (health == null || health.isInvincible || health.isDead) return false;

  health.current -= amount;
  health.invincibleSeconds = invincibilitySeconds;
  world.events.emit(DamageEvent(entity, amount, source: source));
  if (health.isDead) {
    world.events.emit(DeathEvent(entity));
  }

  if (knockbackSpeed > 0 && source != null) {
    final vel = world.storeOf<Velocity>().get(entity);
    final entityPos = world.storeOf<Position>().get(entity);
    final sourcePos = world.storeOf<Position>().get(source);
    if (vel != null && entityPos != null && sourcePos != null) {
      final dx = entityPos.x - sourcePos.x;
      final dy = entityPos.y - sourcePos.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 0) {
        vel.x = dx / dist * knockbackSpeed;
        vel.y = dy / dist * knockbackSpeed;
      }
    }
  }

  if (hitstunSeconds > 0) {
    world.storeOf<PlatformerController>().get(entity)?.hitstunSeconds = hitstunSeconds;
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
///
/// [knockbackSpeed]/[hitstunSeconds] forward straight to [damageEntity]
/// — whichever hazard was actually touched is used as the knockback
/// source, so the pushed entity moves away from *that* spike/enemy,
/// not some fixed direction.
void dealDamageOnTouch(
  World world,
  Set<EntityId> hazards,
  double amount, {
  double invincibilitySeconds = 0.5,
  double knockbackSpeed = 0,
  double hitstunSeconds = 0,
}) {
  world.onCollisionWithAny(hazards, (self, other) {
    damageEntity(
      world,
      other,
      amount,
      invincibilitySeconds: invincibilitySeconds,
      source: self,
      knockbackSpeed: knockbackSpeed,
      hitstunSeconds: hitstunSeconds,
    );
  });
}
