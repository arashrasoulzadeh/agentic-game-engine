export 'src/action.dart';
export 'src/actions/set_velocity_action.dart';
export 'src/behavior.dart';
export 'src/button_hit_test.dart';
export 'src/cinematic.dart';
export 'src/component_registry.dart';
export 'src/component_store.dart';
export 'src/components/ai_state.dart';
export 'src/components/button.dart';
export 'src/components/collider.dart';
export 'src/components/particle.dart';
export 'src/components/particle_emitter.dart';
export 'src/components/position.dart';
export 'src/components/room_exit.dart';
export 'src/components/tile_map.dart';
export 'src/components/tween.dart';
export 'src/components/velocity.dart';
export 'src/entity.dart';
export 'src/event_bus.dart';
export 'src/event_helpers.dart';
export 'src/game_state.dart';
export 'src/level.dart';
export 'src/spatial_hash.dart';
export 'src/system.dart';
export 'src/systems/ai_system.dart';
export 'src/systems/collision_system.dart';
export 'src/systems/movement_system.dart';
export 'src/systems/particle_system.dart';
export 'src/systems/tween_system.dart';
export 'src/tmx_import.dart';
export 'src/world.dart';
export 'src/world_view.dart';

import 'src/components/ai_state.dart';
import 'src/components/button.dart';
import 'src/components/collider.dart';
import 'src/components/particle.dart';
import 'src/components/particle_emitter.dart';
import 'src/components/position.dart';
import 'src/components/room_exit.dart';
import 'src/components/tile_map.dart';
import 'src/components/tween.dart';
import 'src/components/velocity.dart';
import 'src/world.dart';

/// Registers the engine's built-in components on [world]. Games/agents
/// register their own additional component types the same way via
/// `world.components.register<T>(...)`.
///
/// `TileMap` lives here (not `engine_platformer`) even though it was
/// briefly moved there — it's genre-general (RPGs, puzzle games, etc.
/// all use tile grids too, and `engine_flutter`'s renderer needs the
/// type to draw tiles at all); only the *platformer collision logic*
/// against it (`TileCollisionSystem`, which cares about
/// `PlatformerController.grounded`) is platformer-specific and lives in
/// `engine_platformer`. Moving the data type there too would have made
/// `engine_flutter` depend on `engine_platformer` to render it, which
/// is circular since `engine_platformer` depends on `engine_flutter`
/// for sprites/animation — caught by `flutter test` immediately
/// failing to compile across all three packages.
void registerCoreComponents(World world) {
  world.components.register<Position>(
    'position',
    (p) => p.toJson(),
    Position.fromJson,
  );
  world.components.register<Velocity>(
    'velocity',
    (v) => v.toJson(),
    Velocity.fromJson,
  );
  world.components.register<Collider>(
    'collider',
    (c) => c.toJson(),
    Collider.fromJson,
  );
  world.components.register<AIState>(
    'aiState',
    (a) => a.toJson(),
    AIState.fromJson,
  );
  world.components.register<Button>(
    'button',
    (b) => b.toJson(),
    Button.fromJson,
  );
  world.components.register<RoomExit>(
    'roomExit',
    (r) => r.toJson(),
    RoomExit.fromJson,
  );
  world.components.register<TileMap>(
    'tileMap',
    (t) => t.toJson(),
    TileMap.fromJson,
  );
  world.components.register<Particle>(
    'particle',
    (p) => p.toJson(),
    Particle.fromJson,
  );
  world.components.register<ParticleEmitter>(
    'particleEmitter',
    (p) => p.toJson(),
    ParticleEmitter.fromJson,
  );
  world.components.register<Tween>(
    'tween',
    (t) => t.toJson(),
    Tween.fromJson,
  );
}
