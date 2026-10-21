import 'src/rendering/particle_forces.dart';
import 'package:engine_schema/engine_schema.dart';
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
export 'package:engine_schema/engine_schema.dart'
    show FieldSchema, FieldType, ComponentSchema;
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
export 'src/content/level_diff.dart';
export 'src/content/level_format.dart';
export 'src/content/level.dart';
export 'src/command/edit_command.dart';
export 'src/command/entity_commands.dart';
export 'src/command/tile_commands.dart';
export 'src/command/composite_command.dart';
export 'src/command/prefab_commands.dart';
export 'src/content/prefab.dart';
export 'src/content/brush.dart';
export 'src/command/command_history.dart';
export 'src/validation/level_validator.dart';
export 'src/validation/reachability.dart';
export 'src/content/string_table.dart';
export 'src/physics/pathfinding.dart';
export 'src/physics/raycast.dart';
export 'src/physics/spatial_hash.dart';
export 'src/physics/procedural_generation.dart';
export 'src/content/player_options.dart';
export 'src/content/action_aliases.dart';
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
export 'src/physics/tmx_export.dart';
export 'src/ui/trigger_helpers.dart';
export 'src/ecs/world.dart';
export 'src/ecs/world_profiler.dart';
export 'src/net/world_snapshot.dart';
export 'src/net/net_endpoint.dart';
export 'src/net/loopback_link.dart';
export 'src/net/rollback_session.dart';
export 'src/net/lag_compensation.dart';
export 'src/net/state_sync.dart';
export 'src/net/session.dart';
export 'src/ecs/ring_buffer.dart';
export 'src/ecs/world_view.dart';
export 'src/distribution/release_manifest.dart';
export 'src/graph/graph.dart';
export 'src/graph/node_kind.dart';
export 'src/graph/graph_validator.dart';
export 'src/graph/dialogue_compiler.dart';
export 'src/graph/behavior_tree_graph.dart';
export 'src/turn/turn_components.dart';
export 'src/turn/turn_system.dart';
export 'src/turn/order.dart';
export 'src/turn/order_system.dart';
export 'src/turn/grid_navigation.dart';
export 'src/turn/flow_field.dart';
export 'src/turn/formation.dart';
export 'src/turn/economy.dart';
export 'src/turn/gathering.dart';
export 'src/turn/tech.dart';
export 'src/turn/construction.dart';
export 'src/turn/realtime.dart';
export 'src/turn/occupancy.dart';
export 'src/turn/selection.dart';
export 'src/turn/combat.dart';
export 'src/turn/status.dart';
export 'src/turn/objectives.dart';
export 'src/turn/carry.dart';
export 'src/turn/fog_of_war.dart';
export 'src/turn/ai_turn.dart';

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
import 'src/turn/turn_components.dart';
import 'src/turn/order.dart';
import 'src/turn/selection.dart';
import 'src/turn/combat.dart';
import 'src/turn/status.dart';
import 'src/turn/objectives.dart';
import 'src/turn/carry.dart';
import 'src/turn/economy.dart';
import 'src/turn/construction.dart';
import 'src/turn/gathering.dart';
import 'src/turn/tech.dart';
import 'src/turn/realtime.dart';
import 'src/turn/fog_of_war.dart';

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
    schema: positionSchema,
  );
  world.components.register<Velocity>(
    'velocity',
    (v) => v.toJson(),
    Velocity.fromJson,
    schema: velocitySchema,
  );
  world.components.register<Collider>(
    'collider',
    (c) => c.toJson(),
    Collider.fromJson,

    schema: colliderSchema,
  );
  world.components.register<AIState>(
    'aiState',
    (a) => a.toJson(),
    AIState.fromJson,

    schema: aiStateSchema,
  );
  world.components.register<Button>(
    'button',
    (b) => b.toJson(),
    Button.fromJson,
    schema: buttonSchema,
  );
  world.components.register<ButtonHitBox>(
    'buttonHitBox',
    (b) => b.toJson(),
    ButtonHitBox.fromJson,
    schema: buttonHitBoxSchema,
  );
  world.components.register<RoomExit>(
    'roomExit',
    (r) => r.toJson(),
    RoomExit.fromJson,

    schema: roomExitSchema,
  );
  world.components.register<TileMap>(
    'tileMap',
    (t) => t.toJson(),
    TileMap.fromJson,

    schema: tileMapSchema,
  );
  world.components.register<Particle>(
    'particle',
    (p) => p.toJson(),
    Particle.fromJson,

    schema: particleSchema,
  );
  world.components.register<ParticleEmitter>(
    'particleEmitter',
    (p) => p.toJson(),
    ParticleEmitter.fromJson,

    schema: particleEmitterSchema,
  );
  world.components.register<Tween>(
    'tween',
    (t) => t.toJson(),
    Tween.fromJson,
    schema: tweenSchema,
  );
  world.components.register<TriggerZone>(
    'triggerZone',
    (t) => t.toJson(),
    TriggerZone.fromJson,

    schema: triggerZoneSchema,
  );
  world.components.register<Pushable>(
    'pushable',
    (p) => p.toJson(),
    Pushable.fromJson,
    schema: pushableSchema,
  );
  world.components.register<DialogueGraph>(
    'dialogueGraph',
    (d) => d.toJson(),
    DialogueGraph.fromJson,

    schema: dialogueGraphSchema,
  );
  world.components.register<GameState>(
    'gameState',
    (g) => g.toJson(),
    GameState.fromJson,

    schema: gameStateSchema,
  );
  world.components.register<Inventory>(
    'inventory',
    (i) => i.toJson(),
    Inventory.fromJson,

    schema: inventorySchema,
  );
  world.components.register<ParticleForces>(
    'particleForces',
    (p) => p.toJson(),
    ParticleForces.fromJson,

    schema: particleForcesSchema,
  );
  world.components.register<HearingComponent>(
    'hearing',
    (h) => h.toJson(),
    HearingComponent.fromJson,
    schema: hearingSchema,
  );
  world.components.register<SoundEvent>(
    'soundEvent',
    (s) => s.toJson(),
    SoundEvent.fromJson,

    schema: soundEventSchema,
  );
  world.components.register<Team>(
    'team',
    (t) => t.toJson(),
    Team.fromJson,
    schema: teamSchema,
  );
  world.components.register<ActionPoints>(
    'actionPoints',
    (a) => a.toJson(),
    ActionPoints.fromJson,
    schema: actionPointsSchema,
  );
  world.components.register<TurnState>(
    'turnState',
    (t) => t.toJson(),
    TurnState.fromJson,
    schema: turnStateSchema,
  );
  world.components.register<GridPosition>(
    'gridPosition',
    (g) => g.toJson(),
    GridPosition.fromJson,
    schema: gridPositionSchema,
  );
  world.components.register<OrderQueue>(
    'orderQueue',
    (q) => q.toJson(),
    OrderQueue.fromJson,
    schema: orderQueueSchema,
  );
  world.components.register<Selected>(
    'selected',
    (s) => s.toJson(),
    Selected.fromJson,
    schema: selectedSchema,
  );
  world.components.register<UnitStats>(
    'unitStats',
    (u) => u.toJson(),
    UnitStats.fromJson,
    schema: unitStatsSchema,
  );
  world.components.register<Vision>(
    'vision',
    (v) => v.toJson(),
    Vision.fromJson,
    schema: visionSchema,
  );
  world.components.register<FogOfWar>(
    'fogOfWar',
    (f) => f.toJson(),
    FogOfWar.fromJson,
    schema: fogOfWarSchema,
  );
  world.components.register<AttackProfile>(
    'attackProfile',
    (a) => a.toJson(),
    AttackProfile.fromJson,
    schema: attackProfileSchema,
  );
  world.components.register<StatusEffects>(
    'statusEffects',
    (s) => s.toJson(),
    StatusEffects.fromJson,
    schema: statusEffectsSchema,
  );
  world.components.register<Objective>(
    'objective',
    (o) => o.toJson(),
    Objective.fromJson,
    schema: objectiveSchema,
  );
  world.components.register<ObjectiveRules>(
    'objectiveRules',
    (r) => r.toJson(),
    ObjectiveRules.fromJson,
    schema: objectiveRulesSchema,
  );
  world.components.register<RealtimeStats>(
    'realtimeStats',
    (r) => r.toJson(),
    RealtimeStats.fromJson,
    schema: realtimeStatsSchema,
  );
  world.components.register<Vip>(
    'vip',
    (v) => v.toJson(),
    Vip.fromJson,
    schema: vipSchema,
  );
  world.components.register<Flag>(
    'flag',
    (f) => f.toJson(),
    Flag.fromJson,
    schema: flagSchema,
  );
  world.components.register<DeliveryZone>(
    'deliveryZone',
    (z) => z.toJson(),
    DeliveryZone.fromJson,
    schema: deliveryZoneSchema,
  );
  world.components.register<FlagRules>(
    'flagRules',
    (r) => r.toJson(),
    FlagRules.fromJson,
    schema: flagRulesSchema,
  );
  world.components.register<Treasury>(
    'treasury',
    (t) => t.toJson(),
    Treasury.fromJson,
    schema: treasurySchema,
  );
  world.components.register<Producer>(
    'producer',
    (p) => p.toJson(),
    Producer.fromJson,
    schema: producerSchema,
  );
  world.components.register<ResourceNode>(
    'resourceNode',
    (n) => n.toJson(),
    ResourceNode.fromJson,
    schema: resourceNodeSchema,
  );
  world.components.register<Depot>(
    'depot',
    (d) => d.toJson(),
    Depot.fromJson,
    schema: depotSchema,
  );
  world.components.register<Gatherer>(
    'gatherer',
    (g) => g.toJson(),
    Gatherer.fromJson,
    schema: gathererSchema,
  );
  world.components.register<Builder>(
    'builder',
    (b) => b.toJson(),
    Builder.fromJson,
    schema: builderSchema,
  );
  world.components.register<TechState>(
    'techState',
    (t) => t.toJson(),
    TechState.fromJson,
    schema: techStateSchema,
  );
  world.components.register<Provides>(
    'provides',
    (p) => p.toJson(),
    Provides.fromJson,
    schema: providesSchema,
  );
  world.components.register<Construction>(
    'construction',
    (c) => c.toJson(),
    Construction.fromJson,
    schema: constructionSchema,
  );
}
