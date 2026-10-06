import 'src/rendering/particle_forces.dart';
import 'src/schema/component_schema.dart';
import 'src/content/inventory.dart';

export 'src/ecs/action.dart';
export 'src/ai/set_velocity_action.dart';
export 'src/ai/flee_behavior.dart';
export 'src/ai/steering.dart';
export 'src/ai/behavior_tree.dart';
export 'src/ai/state_machine.dart';
export 'src/ai/hearing.dart';
export 'src/ecs/behavior.dart';
export 'src/ui/button_hit_test.dart';
export 'src/content/cinematic.dart';
export 'src/content/inventory.dart';
export 'src/content/dialogue.dart';
export 'src/ecs/component_registry.dart';
export 'src/schema/component_schema.dart';
export 'src/ecs/component_store.dart';
export 'src/ecs/deterministic_random.dart';
export 'src/ecs/replay_recorder.dart';
export 'src/ai/ai_state.dart';
export 'src/ui/button.dart';
export 'src/ui/button_hit_box.dart';
export 'src/physics/collider.dart';
export 'src/rendering/day_night_cycle.dart';
export 'src/rendering/particle.dart';
export 'src/rendering/particle_emitter.dart';
export 'src/rendering/particle_forces.dart';
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
export 'src/content/level_document.dart';
export 'src/content/level.dart';
export 'src/command/edit_command.dart';
export 'src/command/entity_commands.dart';
export 'src/command/command_history.dart';
export 'src/validation/level_validator.dart';
export 'src/validation/reachability.dart';
export 'src/content/string_table.dart';
export 'src/physics/pathfinding.dart';
export 'src/physics/raycast.dart';
export 'src/physics/spatial_hash.dart';
export 'src/physics/procedural_generation.dart';
export 'src/content/player_options.dart';
export 'src/content/analytics.dart';
export 'src/content/localization.dart';
export 'src/ecs/system.dart';
export 'src/ecs/job_system.dart' hide PathPoint;
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
import 'src/ui/button_hit_box.dart';
import 'src/physics/collider.dart';
import 'src/content/dialogue.dart';
import 'src/ai/hearing.dart';
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
import 'src/content/game_state.dart';

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
    schema: const ComponentSchema('position', [
      FieldSchema('x', FieldType.double, defaultValue: 0),
      FieldSchema('y', FieldType.double, defaultValue: 0),
    ]),
  );
  world.components.register<Velocity>(
    'velocity',
    (v) => v.toJson(),
    Velocity.fromJson,
    schema: const ComponentSchema('velocity', [
      FieldSchema('x', FieldType.double, defaultValue: 0),
      FieldSchema('y', FieldType.double, defaultValue: 0),
    ]),
  );
  world.components.register<Collider>(
    'collider',
    (c) => c.toJson(),
    Collider.fromJson,

    schema: const ComponentSchema('collider', [
      FieldSchema('radius', FieldType.double, min: 0),
      FieldSchema('blocksLight', FieldType.bool, defaultValue: false),
      FieldSchema('pushable', FieldType.bool, defaultValue: true),
      FieldSchema('collisionGroup', FieldType.int, defaultValue: 1),
      FieldSchema('collisionMask', FieldType.int, defaultValue: -1),
    ]),
  );
  world.components.register<AIState>(
    'aiState',
    (a) => a.toJson(),
    AIState.fromJson,

    schema: const ComponentSchema('aiState', [
      FieldSchema('behaviorId', FieldType.string),
      FieldSchema('memory', FieldType.object, optional: true),
    ]),
  );
  world.components.register<Button>(
    'button',
    (b) => b.toJson(),
    Button.fromJson,
    schema: const ComponentSchema('button', [
      FieldSchema('actionId', FieldType.string),
    ]),
  );
  world.components.register<ButtonHitBox>(
    'buttonHitBox',
    (b) => b.toJson(),
    ButtonHitBox.fromJson,
    schema: const ComponentSchema('buttonHitBox', [
      FieldSchema('width', FieldType.double, min: 0),
      FieldSchema('height', FieldType.double, min: 0),
    ]),
  );
  world.components.register<RoomExit>(
    'roomExit',
    (r) => r.toJson(),
    RoomExit.fromJson,

    schema: const ComponentSchema('roomExit', [
      FieldSchema('targetSceneId', FieldType.string),
      FieldSchema('spawnPoint', FieldType.string),
    ]),
  );
  world.components.register<TileMap>(
    'tileMap',
    (t) => t.toJson(),
    TileMap.fromJson,

    schema: const ComponentSchema('tileMap', [
      FieldSchema('cols', FieldType.int, min: 1),
      FieldSchema('rows', FieldType.int, min: 1),
      FieldSchema('tileWidth', FieldType.double, min: 0),
      FieldSchema('tileHeight', FieldType.double, min: 0),
      FieldSchema('tiles', FieldType.list),
      FieldSchema('solidTileIds', FieldType.list),
      FieldSchema('oneWayTileIds', FieldType.list),
      FieldSchema('slopeUpRightTileIds', FieldType.list),
      FieldSchema('slopeUpLeftTileIds', FieldType.list),
      FieldSchema('ladderTileIds', FieldType.list),
      FieldSchema('conveyorSpeedByTileId', FieldType.object),
      FieldSchema('frictionByTileId', FieldType.object),
      FieldSchema('atlasId', FieldType.string, optional: true),
      FieldSchema('regionByTileId', FieldType.object),
      FieldSchema('zIndex', FieldType.int, defaultValue: 0),
      FieldSchema('backgroundTiles', FieldType.list, optional: true),
      FieldSchema('foregroundTiles', FieldType.list, optional: true),
      FieldSchema('tileAnimations', FieldType.object, optional: true),
      FieldSchema(
        'tileAnimationFps',
        FieldType.double,
        min: 0,
        defaultValue: 6,
      ),
      FieldSchema('collisionGroups', FieldType.object, optional: true),
    ]),
  );
  world.components.register<Particle>(
    'particle',
    (p) => p.toJson(),
    Particle.fromJson,

    schema: const ComponentSchema('particle', [
      FieldSchema('age', FieldType.double, min: 0),
      FieldSchema('lifetime', FieldType.double, min: 0),
      FieldSchema('startScale', FieldType.double, min: 0),
      FieldSchema('endScale', FieldType.double, min: 0),
      FieldSchema('startAlpha', FieldType.double, min: 0, max: 1),
      FieldSchema('endAlpha', FieldType.double, min: 0, max: 1),
      FieldSchema('colorArgb', FieldType.int),
      FieldSchema('zIndex', FieldType.int),
      FieldSchema('followEmitter', FieldType.bool),
      FieldSchema('emitterEntityId', FieldType.int, optional: true),
    ]),
  );
  world.components.register<ParticleEmitter>(
    'particleEmitter',
    (p) => p.toJson(),
    ParticleEmitter.fromJson,

    schema: const ComponentSchema('particleEmitter', [
      FieldSchema('rate', FieldType.double, min: 0),
      FieldSchema('burstCount', FieldType.int, min: 0),
      FieldSchema('speedMin', FieldType.double, min: 0),
      FieldSchema('speedMax', FieldType.double, min: 0),
      FieldSchema('angleMin', FieldType.double),
      FieldSchema('angleMax', FieldType.double),
      FieldSchema('lifetimeMin', FieldType.double, min: 0),
      FieldSchema('lifetimeMax', FieldType.double, min: 0),
      FieldSchema('startScale', FieldType.double, min: 0),
      FieldSchema('endScale', FieldType.double, min: 0),
      FieldSchema('startAlpha', FieldType.double, min: 0, max: 1),
      FieldSchema('endAlpha', FieldType.double, min: 0, max: 1),
      FieldSchema('colorArgb', FieldType.int),
      FieldSchema('zIndex', FieldType.int),
      FieldSchema(
        'emissionShape',
        FieldType.enumeration,
        options: ['point', 'circle', 'rect', 'edge'],
        defaultValue: 'point',
      ),
      FieldSchema('emissionRadius', FieldType.double, min: 0),
      FieldSchema('emissionHalfWidth', FieldType.double, min: 0),
      FieldSchema('emissionHalfHeight', FieldType.double, min: 0),
      FieldSchema('edgeStartX', FieldType.double),
      FieldSchema('edgeStartY', FieldType.double),
      FieldSchema('edgeEndX', FieldType.double),
      FieldSchema('edgeEndY', FieldType.double),
      FieldSchema('followEmitter', FieldType.bool),
      FieldSchema('accumulator', FieldType.double, min: 0),
    ]),
  );
  world.components.register<Tween>(
    'tween',
    (t) => t.toJson(),
    Tween.fromJson,
    schema: const ComponentSchema('tween', [
      FieldSchema('from', FieldType.double),
      FieldSchema('to', FieldType.double),
      FieldSchema('duration', FieldType.double, min: 0),
      FieldSchema('elapsed', FieldType.double, min: 0),
      FieldSchema('loop', FieldType.bool),
      FieldSchema('pingPong', FieldType.bool),
      FieldSchema(
        'easing',
        FieldType.enumeration,
        options: ['linear', 'easeInQuad', 'easeOutQuad', 'easeInOutQuad'],
        defaultValue: 'linear',
      ),
      FieldSchema('reversed', FieldType.bool),
    ]),
  );
  world.components.register<TriggerZone>(
    'triggerZone',
    (t) => t.toJson(),
    TriggerZone.fromJson,

    schema: const ComponentSchema('triggerZone', [
      FieldSchema('triggerId', FieldType.string),
      FieldSchema('data', FieldType.object, optional: true),
    ]),
  );
  world.components.register<Pushable>(
    'pushable',
    (p) => p.toJson(),
    Pushable.fromJson,
    schema: const ComponentSchema('pushable', [
      FieldSchema('pushSpeed', FieldType.double, min: 0),
    ]),
  );
  world.components.register<DialogueGraph>(
    'dialogueGraph',
    (d) => d.toJson(),
    DialogueGraph.fromJson,

    schema: const ComponentSchema('dialogueGraph', [
      FieldSchema('nodes', FieldType.object),
      FieldSchema('startNodeId', FieldType.string),
      FieldSchema('metadata', FieldType.object, optional: true),
    ]),
  );
  world.components.register<GameState>(
    'gameState',
    (g) => g.toJson(),
    GameState.fromJson,

    schema: const ComponentSchema('gameState', [
      FieldSchema('data', FieldType.object),
      FieldSchema('migrationVersion', FieldType.int, min: 1, defaultValue: 1),
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
  world.components.register<ParticleForces>(
    'particleForces',
    (p) => p.toJson(),
    ParticleForces.fromJson,

    schema: const ComponentSchema('particleForces', [
      FieldSchema('radius', FieldType.double, min: 0, defaultValue: 100),
      FieldSchema('strength', FieldType.double, defaultValue: 500),
      FieldSchema('isWind', FieldType.bool, defaultValue: false),
      FieldSchema('windDirection', FieldType.double, defaultValue: 0),
      FieldSchema('falloffExponent', FieldType.double, min: 0, defaultValue: 2),
    ]),
  );
  world.components.register<HearingComponent>(
    'hearing',
    (h) => h.toJson(),
    HearingComponent.fromJson,
    schema: const ComponentSchema('hearing', [
      FieldSchema('range', FieldType.double, min: 0),
    ]),
  );
  world.components.register<SoundEvent>(
    'soundEvent',
    (s) => s.toJson(),
    SoundEvent.fromJson,

    schema: const ComponentSchema('soundEvent', [
      FieldSchema('x', FieldType.double),
      FieldSchema('y', FieldType.double),
      FieldSchema('loudness', FieldType.double, min: 0),
      FieldSchema('tag', FieldType.string, optional: true),
      FieldSchema('data', FieldType.object, optional: true),
    ]),
  );
}
