export 'src/behaviors/follow_behavior.dart';
export 'src/behaviors/patrol_behavior.dart';
export 'src/collision_math.dart';
export 'src/components/gravity.dart';
export 'src/components/movement_animation_set.dart';
export 'src/components/platform_body.dart';
export 'src/components/platformer_controller.dart';
export 'src/spawn_helpers.dart';
export 'src/systems/facing_system.dart';
export 'src/systems/gravity_system.dart';
export 'src/systems/jump_system.dart';
export 'src/systems/movement_animation_system.dart';
export 'src/systems/platformer_input_system.dart';
export 'src/systems/platformer_system.dart';
export 'src/systems/tile_collision_system.dart';

import 'package:engine_core/engine_core.dart';

import 'src/components/gravity.dart';
import 'src/components/movement_animation_set.dart';
import 'src/components/platform_body.dart';
import 'src/components/platformer_controller.dart';

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
}
