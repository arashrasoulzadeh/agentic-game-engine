export 'src/ecs/action.dart';
export 'src/ai/set_velocity_action.dart';
export 'src/ecs/behavior.dart';
export 'src/ui/button_hit_test.dart';
export 'src/content/cinematic.dart';
export 'src/ecs/component_registry.dart';
export 'src/ecs/component_store.dart';
export 'src/ecs/deterministic_random.dart';
export 'src/ecs/replay_recorder.dart';
export 'src/ai/ai_state.dart';
export 'src/ui/button.dart';
export 'src/physics/collider.dart';
export 'src/rendering/day_night_cycle.dart';
export 'src/rendering/particle.dart';
export 'src/rendering/particle_emitter.dart';
export 'src/physics/position.dart';
export 'src/physics/pushable.dart';
export 'src/ui/room_exit.dart';
export 'src/physics/tile_animation_system.dart';
export 'src/physics/autotile.dart';
export 'src/physics/tile_map.dart';
export 'src/ui/trigger_zone.dart';
export 'src/rendering/tween.dart';
export 'src/physics/velocity.dart';
export 'src/ecs/entity.dart';
export 'src/ecs/event_bus.dart';
export 'src/ecs/event_helpers.dart';
export 'src/content/game_state.dart';
export 'src/content/level.dart';
export 'src/content/string_table.dart';
export 'src/physics/pathfinding.dart';
export 'src/physics/raycast.dart';
export 'src/physics/spatial_hash.dart';
export 'src/ecs/system.dart';
export 'src/ai/ai_system.dart';
export 'src/physics/collision_system.dart';
export 'src/physics/movement_system.dart';
export 'src/rendering/particle_system.dart';
export 'src/physics/pushable_system.dart';
export 'src/rendering/tween_system.dart';
export 'src/physics/tmx_import.dart';
export 'src/ui/trigger_helpers.dart';
export 'src/ecs/world.dart';
export 'src/ecs/world_view.dart';

import 'src/ai/ai_state.dart';
import 'src/ui/button.dart';
import 'src/physics/collider.dart';
import 'src/rendering/particle.dart';
import 'src/rendering/particle_emitter.dart';
import 'src/physics/position.dart';
import 'src/physics/pushable.dart';
import 'src/ui/room_exit.dart';
import 'src/physics/tile_map.dart';
import 'src/ui/trigger_zone.dart';
import 'src/rendering/tween.dart';
import 'src/physics/velocity.dart';
import 'src/ecs/world.dart';

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
  world.components.register<TriggerZone>(
    'triggerZone',
    (t) => t.toJson(),
    TriggerZone.fromJson,
  );
  world.components.register<Pushable>(
    'pushable',
    (p) => p.toJson(),
    Pushable.fromJson,
  );
}
