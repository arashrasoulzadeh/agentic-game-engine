export 'src/physics/platformer_pathfinding.dart';
export 'src/ai/avoidance_behavior.dart';
export 'src/ai/enemy_combat.dart';
export 'src/ai/follow_behavior.dart';
export 'src/ai/investigate_behavior.dart';
export 'src/ai/path_follow_behavior.dart';
export 'src/ai/patrol_behavior.dart';
export 'src/logic/checkpoint_helpers.dart';
export 'src/physics/collision_math.dart';
export 'src/logic/boss_phase_system.dart';
export 'src/logic/combat_helpers.dart';
export 'src/logic/checkpoint.dart';
export 'src/physics/gravity.dart';
export 'src/logic/health.dart';
export 'src/logic/parry.dart';
export 'src/ui/health_hud_link.dart';
export 'src/logic/last_checkpoint.dart';
export 'src/rendering/movement_animation_set.dart';
export 'src/rendering/jump_animation_set.dart';
export 'src/physics/platform_body.dart';
export 'src/physics/platformer_controller.dart';
export 'src/logic/projectile.dart';
export 'src/ui/hud_helpers.dart';
export 'src/logic/pickup_helpers.dart';
export 'src/logic/projectile_helpers.dart';
export 'src/logic/weapon.dart';
export 'src/spawn_helpers.dart';
export 'src/system_pack.dart';
export 'src/physics/attack_system.dart';
export 'src/physics/dash_system.dart';
export 'src/rendering/facing_system.dart';
export 'src/physics/gravity_system.dart';
export 'src/ui/health_hud_system.dart';
export 'src/logic/health_system.dart';
export 'src/physics/hitstun_system.dart';
export 'src/physics/jump_system.dart';
export 'src/physics/ladder_system.dart';
export 'src/physics/ledge_grab_system.dart';
export 'src/rendering/movement_animation_system.dart';
export 'src/rendering/jump_animation_system.dart';
export 'src/physics/platformer_input_system.dart';
export 'src/physics/platformer_system.dart';
export 'src/logic/projectile_system.dart';
export 'src/physics/tile_collision_system.dart';
export 'src/physics/water_zone.dart';
export 'src/physics/water_physics_system.dart';

import 'package:engine_core/engine_core.dart';

import 'src/logic/checkpoint.dart';
import 'src/physics/gravity.dart';
import 'src/logic/health.dart';
import 'src/logic/parry.dart';
import 'src/ui/health_hud_link.dart';
import 'src/ai/enemy_combat.dart';
import 'src/logic/last_checkpoint.dart';
import 'src/rendering/movement_animation_set.dart';
import 'src/rendering/jump_animation_set.dart';
import 'src/physics/platform_body.dart';
import 'src/physics/platformer_controller.dart';
import 'src/logic/projectile.dart';
import 'src/logic/weapon.dart';
import 'src/physics/water_zone.dart';

/// Registers this package's genre-specific components on [world],
/// alongside `registerCoreComponents`/`registerFlutterComponents`.
/// `TileMap` itself is registered by `registerCoreComponents` (it's
/// genre-general, not platformer-specific) — only the collision
/// components live here.
void registerPlatformerComponents(World world) {
  world.components.register<Gravity>(
    'gravity',
    (g) => g.toJson(),
    Gravity.fromJson,
 
    schema: const ComponentSchema('gravity', [
      FieldSchema('scale', FieldType.double, min: 0, defaultValue: 1),
      FieldSchema('fallMultiplier', FieldType.double, min: 0, defaultValue: 1),
    ]),
  );
  world.components.register<PlatformBody>(
    'platformBody',
    (p) => p.toJson(),
    PlatformBody.fromJson,
 
    schema: const ComponentSchema('platformBody', [
      FieldSchema('width', FieldType.double, min: 0),
      FieldSchema('height', FieldType.double, min: 0),
      FieldSchema('oneWay', FieldType.bool, defaultValue: false),
    ]),
  );
  world.components.register<PlatformerController>(
    'platformerController',
    (p) => p.toJson(),
    PlatformerController.fromJson,
 
    schema: const ComponentSchema('platformerController', [
      FieldSchema('grounded', FieldType.bool, defaultValue: false),
      FieldSchema('jumpSpeed', FieldType.double, min: 0, defaultValue: 300),
      FieldSchema('jumpRequested', FieldType.bool),
      FieldSchema('coyoteTimeSeconds', FieldType.double, min: 0),
      FieldSchema('jumpBufferSeconds', FieldType.double, min: 0),
      FieldSchema('maxAirJumps', FieldType.int, min: 0),
      FieldSchema('wallJumpPushSpeed', FieldType.double, min: 0),
      FieldSchema('wallSlideMaxFallSpeed', FieldType.double, min: 0, optional: true),
      FieldSchema('dashSpeed', FieldType.double, min: 0),
      FieldSchema('dashDurationSeconds', FieldType.double, min: 0),
      FieldSchema('jumpCutMultiplier', FieldType.double, min: 0),
      FieldSchema('timeSinceGrounded', FieldType.double, min: 0),
      FieldSchema('timeSinceJumpPressed', FieldType.double, min: 0),
      FieldSchema('airJumpsUsed', FieldType.int, min: 0),
      FieldSchema('touchingWallLeft', FieldType.bool),
      FieldSchema('touchingWallRight', FieldType.bool),
      FieldSchema('dashRequested', FieldType.bool),
      FieldSchema('dashTimeRemaining', FieldType.double, min: 0),
      FieldSchema('dashUsed', FieldType.bool),
      FieldSchema('jumpHeldLastTick', FieldType.bool),
      FieldSchema('hitstunSeconds', FieldType.double, min: 0),
      FieldSchema('facingSign', FieldType.double),
      FieldSchema('climbSpeed', FieldType.double, min: 0),
      FieldSchema('onLadder', FieldType.bool),
      FieldSchema('groundFriction', FieldType.double, min: 0),
      FieldSchema('ledgeGrabEnabled', FieldType.bool),
      FieldSchema('ledgeGrabbing', FieldType.bool),
      FieldSchema('ledgeMantleTargetX', FieldType.double),
      FieldSchema('ledgeMantleTargetY', FieldType.double),
      FieldSchema('inWater', FieldType.bool),
    ]),
  );
  world.components.register<MovementAnimationSet>(
    'movementAnimationSet',
    (m) => m.toJson(),
    MovementAnimationSet.fromJson,
 
    schema: const ComponentSchema('movementAnimationSet', [
      FieldSchema('idle', FieldType.object),
      FieldSchema('walk', FieldType.object),
      FieldSchema('jump', FieldType.object, optional: true),
      FieldSchema('moveThreshold', FieldType.double, min: 0),
    ]),
  );
  world.components.register<JumpAnimationSet>(
    'jumpAnimationSet',
    (j) => j.toJson(),
    JumpAnimationSet.fromJson,
 
    schema: const ComponentSchema('jumpAnimationSet', [
      FieldSchema('start', FieldType.object),
      FieldSchema('rising', FieldType.object),
      FieldSchema('peak', FieldType.object),
      FieldSchema('falling', FieldType.object),
      FieldSchema('landing', FieldType.object),
      FieldSchema('completed', FieldType.object),
      FieldSchema('peakVelocityThreshold', FieldType.double, min: 0),
      FieldSchema('startHoldSeconds', FieldType.double, min: 0),
      FieldSchema('landingHoldSeconds', FieldType.double, min: 0),
      FieldSchema('completedHoldSeconds', FieldType.double, min: 0),
      FieldSchema('moveInterruptThreshold', FieldType.double, min: 0),
    ]),
  );
  world.components.register<JumpAnimationPhaseState>(
    'jumpAnimationPhaseState',
    (j) => j.toJson(),
    JumpAnimationPhaseState.fromJson,
 
    schema: const ComponentSchema('jumpAnimationPhaseState', [
      FieldSchema('elapsed', FieldType.double, min: 0),
    ]),
  );
  world.components.register<Health>(
    'health',
    (h) => h.toJson(),
    Health.fromJson,
 
    schema: const ComponentSchema('health', [
      FieldSchema('current', FieldType.double, min: 0),
      FieldSchema('max', FieldType.double, min: 1),
      FieldSchema('invincibleSeconds', FieldType.double, min: 0),
      FieldSchema('isGuarding', FieldType.bool, defaultValue: false),
      FieldSchema('guardDamageReduction', FieldType.double, min: 0, max: 1, defaultValue: 1),
      FieldSchema('stability', FieldType.double, min: 0),
      FieldSchema('maxStability', FieldType.double, min: 0),
      FieldSchema('guardBreakStunSeconds', FieldType.double, min: 0),
      FieldSchema('guardBreakTimer', FieldType.double, min: 0),
      FieldSchema('stabilityRegenPerSecond', FieldType.double, min: 0),
    ]),
  );
  world.components.register<Checkpoint>(
    'checkpoint',
    (c) => c.toJson(),
    Checkpoint.fromJson,
 
    schema: const ComponentSchema('checkpoint', [
      FieldSchema('id', FieldType.string),
      FieldSchema('activated', FieldType.bool, defaultValue: false),
    ]),
  );
  world.components.register<LastCheckpoint>(
    'lastCheckpoint',
    (l) => l.toJson(),
    LastCheckpoint.fromJson,
 
    schema: const ComponentSchema('lastCheckpoint', [
      FieldSchema('x', FieldType.double),
      FieldSchema('y', FieldType.double),
    ]),
  );
  world.components.register<Inventory>(
    'inventory',
    (i) => i.toJson(),
    Inventory.fromJson,
 
    schema: const ComponentSchema('inventory', [
      FieldSchema('items', FieldType.object),
    ]),
  );
  world.components.register<Projectile>(
    'projectile',
    (p) => p.toJson(),
    Projectile.fromJson,
 
    schema: const ComponentSchema('projectile', [
      FieldSchema('damage', FieldType.double, min: 0),
      FieldSchema('lifetimeSeconds', FieldType.double, min: 0),
      FieldSchema('elapsed', FieldType.double, min: 0),
      FieldSchema('owner', FieldType.int, optional: true),
    ]),
  );
  world.components.register<HealthHudLink>(
    'healthHudLink',
    (h) => h.toJson(),
    HealthHudLink.fromJson,
 
    schema: const ComponentSchema('healthHudLink', [
      FieldSchema('source', FieldType.int),
    ]),
  );
  world.components.register<WaterZone>(
    'waterZone',
    (w) => w.toJson(),
    WaterZone.fromJson,
 
    schema: const ComponentSchema('waterZone', [
      FieldSchema('width', FieldType.double, min: 0),
      FieldSchema('height', FieldType.double, min: 0),
      FieldSchema('maxFallSpeed', FieldType.double, min: 0),
      FieldSchema('swimUpSpeed', FieldType.double, min: 0),
    ]),
  );
  world.components.register<Weapon>(
    'weapon',
    (w) => w.toJson(),
    Weapon.fromJson,
 
    schema: const ComponentSchema('weapon', [
      FieldSchema('kind', FieldType.enumeration, options: ['melee', 'ranged'], defaultValue: 'melee'),
      FieldSchema('damage', FieldType.double, min: 0),
      FieldSchema('cooldownSeconds', FieldType.double, min: 0),
      FieldSchema('cooldownRemaining', FieldType.double, min: 0),
      FieldSchema('meleeRange', FieldType.double, min: 0),
      FieldSchema('meleeRadius', FieldType.double, min: 0),
      FieldSchema('meleeDurationSeconds', FieldType.double, min: 0),
      FieldSchema('projectileSpeed', FieldType.double, min: 0),
      FieldSchema('projectileRadius', FieldType.double, min: 0),
      FieldSchema('projectileLifetimeSeconds', FieldType.double, min: 0),
      FieldSchema('comboCount', FieldType.int, min: 0),
      FieldSchema('comboWindowSeconds', FieldType.double, min: 0),
      FieldSchema('comboTimer', FieldType.double, min: 0),
      FieldSchema('currentComboStep', FieldType.int, min: 0),
      FieldSchema('comboDamageMultipliers', FieldType.list, optional: true),
      FieldSchema('comboCooldowns', FieldType.list, optional: true),
      FieldSchema('comboMeleeRanges', FieldType.list, optional: true),
      FieldSchema('comboMeleeRadii', FieldType.list, optional: true),
      FieldSchema('comboMeleeDurations', FieldType.list, optional: true),
      FieldSchema('atlasId', FieldType.string, optional: true),
      FieldSchema('spriteRegion', FieldType.string, optional: true),
    ]),
  );
  world.components.register<EnemyCombat>(
    'enemyCombat',
    (e) => e.toJson(),
    EnemyCombat.fromJson,
 
    schema: const ComponentSchema('enemyCombat', [
      FieldSchema('state', FieldType.enumeration, options: ['idle', 'patrol', 'alert', 'approach', 'telegraph', 'attack', 'recovery', 'reposition', 'stagger', 'guard', 'retreat']),
      FieldSchema('stateTimer', FieldType.double, min: 0),
      FieldSchema('target', FieldType.int, optional: true),
      FieldSchema('detectionRange', FieldType.double, min: 0),
      FieldSchema('engageRange', FieldType.double, min: 0),
      FieldSchema('attackRange', FieldType.double, min: 0),
      FieldSchema('telegraphDuration', FieldType.double, min: 0),
      FieldSchema('attackDuration', FieldType.double, min: 0),
      FieldSchema('recoveryDuration', FieldType.double, min: 0),
      FieldSchema('repositionDuration', FieldType.double, min: 0),
      FieldSchema('staggerDuration', FieldType.double, min: 0),
      FieldSchema('guardDuration', FieldType.double, min: 0),
      FieldSchema('retreatHealthFraction', FieldType.double, min: 0, max: 1),
      FieldSchema('approachSpeed', FieldType.double, min: 0),
      FieldSchema('repositionSpeed', FieldType.double, min: 0),
      FieldSchema('retreatSpeed', FieldType.double, min: 0),
      FieldSchema('patrolSpeed', FieldType.double, min: 0),
      FieldSchema('patrolMinX', FieldType.double, optional: true),
      FieldSchema('patrolMaxX', FieldType.double, optional: true),
    ]),
  );
  world.components.register<Parry>(
    'parry',
    (p) => p.toJson(),
    Parry.fromJson,
 
    schema: const ComponentSchema('parry', [
      FieldSchema('parryTimer', FieldType.double, min: 0),
      FieldSchema('parryCooldownTimer', FieldType.double, min: 0),
      FieldSchema('parryWindowSeconds', FieldType.double, min: 0),
      FieldSchema('parryStunSeconds', FieldType.double, min: 0),
      FieldSchema('parryCooldownSeconds', FieldType.double, min: 0),
    ]),
  );
}
