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
export 'src/logic/inventory.dart';
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
import 'src/logic/inventory.dart';
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
  );
  world.components.register<PlatformBody>(
    'platformBody',
    (p) => p.toJson(),
    PlatformBody.fromJson,
  );
  world.components.register<PlatformerController>(
    'platformerController',
    (p) => p.toJson(),
    PlatformerController.fromJson,
  );
  world.components.register<MovementAnimationSet>(
    'movementAnimationSet',
    (m) => m.toJson(),
    MovementAnimationSet.fromJson,
  );
  world.components.register<JumpAnimationSet>(
    'jumpAnimationSet',
    (j) => j.toJson(),
    JumpAnimationSet.fromJson,
  );
  world.components.register<JumpAnimationPhaseState>(
    'jumpAnimationPhaseState',
    (j) => j.toJson(),
    JumpAnimationPhaseState.fromJson,
  );
  world.components.register<Health>(
    'health',
    (h) => h.toJson(),
    Health.fromJson,
  );
  world.components.register<Checkpoint>(
    'checkpoint',
    (c) => c.toJson(),
    Checkpoint.fromJson,
  );
  world.components.register<LastCheckpoint>(
    'lastCheckpoint',
    (l) => l.toJson(),
    LastCheckpoint.fromJson,
  );
  world.components.register<Inventory>(
    'inventory',
    (i) => i.toJson(),
    Inventory.fromJson,
  );
  world.components.register<Projectile>(
    'projectile',
    (p) => p.toJson(),
    Projectile.fromJson,
  );
  world.components.register<HealthHudLink>(
    'healthHudLink',
    (h) => h.toJson(),
    HealthHudLink.fromJson,
  );
  world.components.register<WaterZone>(
    'waterZone',
    (w) => w.toJson(),
    WaterZone.fromJson,
  );
  world.components.register<Weapon>(
    'weapon',
    (w) => w.toJson(),
    Weapon.fromJson,
  );
  world.components.register<EnemyCombat>(
    'enemyCombat',
    (e) => e.toJson(),
    EnemyCombat.fromJson,
  );
  world.components.register<Parry>(
    'parry',
    (p) => p.toJson(),
    Parry.fromJson,
  );
}
