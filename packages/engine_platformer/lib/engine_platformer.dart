export 'src/behaviors/follow_behavior.dart';
export 'src/behaviors/patrol_behavior.dart';
export 'src/checkpoint_helpers.dart';
export 'src/collision_math.dart';
export 'src/combat_helpers.dart';
export 'src/components/checkpoint.dart';
export 'src/components/gravity.dart';
export 'src/components/health.dart';
export 'src/components/inventory.dart';
export 'src/components/last_checkpoint.dart';
export 'src/components/movement_animation_set.dart';
export 'src/components/platform_body.dart';
export 'src/components/platformer_controller.dart';
export 'src/components/projectile.dart';
export 'src/pickup_helpers.dart';
export 'src/projectile_helpers.dart';
export 'src/spawn_helpers.dart';
export 'src/system_pack.dart';
export 'src/systems/dash_system.dart';
export 'src/systems/facing_system.dart';
export 'src/systems/gravity_system.dart';
export 'src/systems/health_system.dart';
export 'src/systems/jump_system.dart';
export 'src/systems/movement_animation_system.dart';
export 'src/systems/platformer_input_system.dart';
export 'src/systems/platformer_system.dart';
export 'src/systems/projectile_system.dart';
export 'src/systems/tile_collision_system.dart';

import 'package:engine_core/engine_core.dart';

import 'src/components/checkpoint.dart';
import 'src/components/gravity.dart';
import 'src/components/health.dart';
import 'src/components/inventory.dart';
import 'src/components/last_checkpoint.dart';
import 'src/components/movement_animation_set.dart';
import 'src/components/platform_body.dart';
import 'src/components/platformer_controller.dart';
import 'src/components/projectile.dart';

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
}
