import '../ai/ai_state.dart';
import '../ai/hearing.dart';
import '../content/big_treasury.dart';
import '../content/dialogue.dart';
import '../content/game_state.dart';
import '../content/inventory.dart';
import 'countdown_timer.dart';
import 'hierarchy.dart';
import 'tags.dart';
import 'world.dart';
import '../physics/collider.dart';
import '../physics/position.dart';
import '../physics/pushable.dart';
import '../physics/tile_map.dart';
import '../physics/velocity.dart';
import '../rendering/particle.dart';
import '../rendering/particle_emitter.dart';
import '../rendering/particle_forces.dart';
import '../rendering/tween.dart';
import '../turn/carry.dart';
import '../turn/combat.dart';
import '../turn/construction.dart';
import '../turn/economy.dart';
import '../turn/fog_of_war.dart';
import '../turn/footprint.dart';
import '../turn/gathering.dart';
import '../turn/objectives.dart';
import '../turn/order.dart';
import '../turn/realtime.dart';
import '../turn/selection.dart';
import '../turn/status.dart';
import '../turn/tech.dart';
import '../turn/turn_components.dart';
import '../ui/button.dart';
import '../ui/button_hit_box.dart';
import '../ui/room_exit.dart';
import '../ui/trigger_zone.dart';
import 'package:engine_schema/engine_schema.dart';

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
  world.components.register<GridFootprint>(
    'gridFootprint',
    (f) => f.toJson(),
    GridFootprint.fromJson,
    schema: gridFootprintSchema,
  );
  world.components.register<OrderQueue>(
    'orderQueue',
    (q) => q.toJson(),
    OrderQueue.fromJson,
    schema: orderQueueSchema,
  );
  world.components.register<CountdownTimer>(
    'countdownTimer',
    (t) => t.toJson(),
    CountdownTimer.fromJson,
    schema: countdownTimerSchema,
  );
  world.components.register<Parent>(
    'parent',
    (p) => p.toJson(),
    Parent.fromJson,
    schema: parentSchema,
  );
  world.components.register<EntityTags>(
    'tags',
    (t) => t.toJson(),
    EntityTags.fromJson,
    schema: tagsSchema,
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
  world.components.register<BigTreasury>(
    'bigTreasury',
    (t) => t.toJson(),
    BigTreasury.fromJson,
    schema: bigTreasurySchema,
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
  world.components.register<BuildWorker>(
    'builder',
    (b) => b.toJson(),
    BuildWorker.fromJson,
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
