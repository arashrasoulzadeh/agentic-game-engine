# SIMPLER (detailed, agent-friendly)

One-by-one checklist with concrete steps to implement/verify each piece. Check items off as you go. Engine code only (`packages/engine_core`, `packages/engine_schema`, `packages/engine_platformer`, `packages/engine_strategy`, `packages/engine_flutter`, etc. as relevant). Gitignored (`test_game/`, `examples/`, `zahaak/`, `mobarez/`) out of scope.

## Setup
  1. `cd packages/engine_core`  
  2. Ensure `pubspec_overrides.yaml` points `engine_schema` to `../engine_schema` (local monorepo).  
  3. Run `dart pub get --offline` if pub.dev unreachable, else `dart pub get`.  
  Files: `packages/engine_core/pubspec.yaml`, `packages/engine_core/pubspec_overrides.yaml`

  1. `cd packages/engine_core && dart analyze --fatal-infos`  
  2. Fix all issues (info/warnings treated fatal).  
  Files: all `lib/**/*.dart`

  1. `cd packages/engine_core && dart test`  
  2. All tests must pass. See `test/` for coverage of features.  
  Files: `packages/engine_core/test/**/*.dart`

  1. `dart pub global run coverage:test_with_coverage` in `packages/engine_core` (or equivalent).  
  2. Verify `coverage/lcov.info` shows 100% line coverage.  
  Files: `packages/engine_core/coverage_integration/lcov.info`, tooling.

## Core entry points
  1. Call `registerCoreComponents(world)` from `package:engine_core/engine_core.dart`.  
  2. Verify registration includes Position/Velocity/Collider/TileMap/AIState/Particle/ParticleEmitter/Tween/etc., all turn components, content components.  
  Steps: inspect `lib/engine_core.dart` `registerCoreComponents` (ends around line ~450+), ensure each component registered with name, toJson/fromJson, schema.  
  Files: `packages/engine_core/lib/engine_core.dart`, `packages/engine_core/lib/src/ecs/component_registry.dart`

  1. Construct `World(width: ..., height: ...)` from `lib/src/ecs/world.dart`.  
  2. Owns `entities`, `components`, `events`, `_systems`.  
  Verify: `World` class exists with expected fields/methods.  
  Files: `packages/engine_core/lib/src/ecs/world.dart`

  1. `final id = world.spawn();` creates entity via `EntityManager`.  
  2. `world.destroy(id)` removes from all component stores, destroys entity, updates archetypes.  
  Files: `packages/engine_core/lib/src/ecs/world.dart`, `packages/engine_core/lib/src/ecs/entity.dart`, `packages/engine_core/lib/src/ecs/archetype.dart`

  1. Returns `ComponentStore<T>` via `components.storeOf<T>()`.  
  2. Use for get/set/has/entityAt etc.  
  Files: `packages/engine_core/lib/src/ecs/world.dart`, `packages/engine_core/lib/src/ecs/component_store.dart`

  1. `world.addSystem(system)` appends to `_systems` (execution order).  
  2. `world.systemOrder` returns names.  
  Files: `packages/engine_core/lib/src/ecs/world.dart`, `packages/engine_core/lib/src/ecs/system.dart`

  1. Sets `_deltaTime = dt`, runs each system in order via `system.update(world, dt)`, then `events.flush()`, increments `_tick`.  
  2. With profiler set, uses timed path.  
  Files: `packages/engine_core/lib/src/ecs/world.dart`

  1. `toJson()` returns `{'tick','width','height','entities':[{'id','components':{...}}]}` serializing via `components.serializeEntity(id)`.  
  2. `applyPatch(patch)` validates shape (throws `WorldPatchException` on bad shape), skips dead entities, applies components via `components.applyToEntity`.  
  Files: `packages/engine_core/lib/src/ecs/world.dart`, `packages/engine_core/lib/src/ecs/component_registry.dart`

## Components

(Verify each has `toJson/fromJson`, registered in `registerCoreComponents` with schema.)

## Systems (built-in)

Add to world: `world.addSystem(MovementSystem());` etc.

## Events

## Agent-facing API

## Built-in behaviors

Tests: `test/doc_examples_ai_test.dart`, `test/ai_system_test.dart`.

## Pathfinding & physics

## Turn-based strategy (`lib/src/turn/`)

## Content

## Testing & benchmarks

## Quick verification commands
```bash
cd packages/engine_core
dart pub get --offline  # or dart pub get
dart analyze --fatal-infos
dart test
# coverage
dart pub global run coverage:test_with_coverage 2>&1 | tail -5
```

## Tips for agents
- Always read the file before editing.  
- Register new components in `registerCoreComponents` and add schema + tests.  
- Follow system ordering (Movement/Collision/Particles/Tween as appropriate).  
- Keep engine_core Flutter-free.  
- Use `WorldView` in behaviors (no direct world mutation).  
- Serialize via `toJson/fromJson` and keep JSON stable.

## Engine Schema (`packages/engine_schema`)
- [ ] **Schema package exists**  
  1. Verify `packages/engine_schema/` has `pubspec.yaml`, `lib/`.  
  2. Used by `engine_core` via path/git override.  
  Files: `packages/engine_schema/pubspec.yaml`, `packages/engine_schema/lib/`

- [ ] **FieldSchema/FieldType/ComponentSchema exported**  
  1. Exported from `engine_core` as `package:engine_schema/engine_schema.dart` show `FieldSchema, FieldType, ComponentSchema`.  
  2. Used for component schemas in registration.  
  Files: `packages/engine_core/lib/engine_core.dart`, `packages/engine_schema/lib/engine_schema.dart`

- [ ] **Component schemas defined for built-ins**  
  1. Ensure schemas exist for Position, Velocity, Collider, TileMap, AIState, Particle, ParticleEmitter, Tween, etc.  
  2. Used by `ComponentRegistry.register` with `schema:` parameter.  
  Files: `packages/engine_core/lib/engine_core.dart` (imports show schema usage)

## ECS Deep Dive
- [ ] **EntityManager**  
  1. Create/destroy entities, track alive set.  
  2. Test entity lifecycle.  
  Files: `packages/engine_core/lib/src/ecs/entity.dart`

- [ ] **ComponentStore<T>**  
  1. Dense/sparse storage, get/set/has/remove, iterate.  
  2. Archetype integration.  
  Files: `packages/engine_core/lib/src/ecs/component_store.dart`

- [ ] **ComponentRegistry**  
  1. Register components with encoder/decoder/schema.  
  2. `serializeEntity`, `applyToEntity`, `all` accessors.  
  3. Throws `ComponentApplyException` on bad component JSON.  
  Files: `packages/engine_core/lib/src/ecs/component_registry.dart`

- [ ] **ArchetypeManager**  
  1. Groups entities by component signature for efficient queries.  
  2. Updated on add/remove/destroy.  
  Files: `packages/engine_core/lib/src/ecs/archetype.dart`

- [ ] **System interface**  
  1. `String get name`, `void update(World world, double dt)`.  
  Files: `packages/engine_core/lib/src/ecs/system.dart`

- [ ] **JobSystem**  
  1. Multithreaded work (collision broadphase/pathfinding). Lazy init. `world.jobSystem`.  
  2. `dispose()` shuts down.  
  Files: `packages/engine_core/lib/src/ecs/job_system.dart`

- [ ] **WorldProfiler**  
  1. Time systems/steps when attached to world.  
  Files: `packages/engine_core/lib/src/ecs/world_profiler.dart`

- [ ] **DeterministicRandom**  
  1. Seeded RNG for deterministic simulation.  
  Files: `packages/engine_core/lib/src/ecs/deterministic_random.dart`

- [ ] **ReplayRecorder**  
  1. Record/replay inputs/events.  
  Files: `packages/engine_core/lib/src/ecs/replay_recorder.dart`

- [ ] **RingBuffer**  
  1. Efficient circular buffer.  
  Files: `packages/engine_core/lib/src/ecs/ring_buffer.dart`

- [ ] **Action/NoOpAction/FailureAction**  
  1. Action interface with `apply(World)`.  
  2. Used by behaviors.  
  Files: `packages/engine_core/lib/src/ecs/action.dart`

## Physics & Collision Details
- [ ] **MovementSystem integration**  
  1. Applies velocity to position: `pos += vel * dt`.  
  2. Bounces off world bounds (`world.width/height`).  
  Test: `test/movement_system_test.dart`

- [ ] **CollisionSystem circle-circle**  
  1. Checks pairs, emits `CollisionEvent(a,b,normal,penetration)`.  
  2. Flushed via events.  
  Test: `test/collision_system_test.dart`

- [ ] **Collider component**  
  1. Circle collider with radius.  
  Files: `packages/engine_core/lib/src/physics/collider.dart`

- [ ] **Pushable/PushableSystem**  
  1. Pushable objects, push resolution.  
  Files: `packages/engine_core/lib/src/physics/pushable.dart`, `packages/engine_core/lib/src/physics/pushable_system.dart`

- [ ] **TileCollision/TileMap physics**  
  1. TileMap defines solid/one-way tiles. Platformer-specific collision lives in `engine_platformer` (TileCollisionSystem) but TileMap data in core.  
  Files: `packages/engine_core/lib/src/physics/tile_map.dart`, `packages/engine_platformer/lib/...`

- [ ] **Autotile**  
  1. Auto-tiling helpers.  
  Files: `packages/engine_core/lib/src/physics/autotile.dart`

- [ ] **TileAnimationSystem**  
  1. Animates tiles.  
  Files: `packages/engine_core/lib/src/physics/tile_animation_system.dart`

- [ ] **TMX import/export**  
  1. `tmx_import.dart` parses Tiled TMX, `tmx_export.dart` exports.  
  Tests: `test/tmx_import_test.dart`

- [ ] **Procedural generation**  
  1. BSP/dungeon generation helpers.  
  Tests: `test/procedural_generation_test.dart`

## Pathfinding & Spatial
- [ ] **A* pathfinding**  
  1. `findPath` over TileMap grid with mapOrigin. Returns path.  
  Test: `test/pathfinding_test.dart`

- [ ] **Raycast**  
  1. `raycastTileMap` against tile geometry.  
  Test: `test/raycast_test.dart`

- [ ] **SpatialHash**  
  1. Grid-based spatial partitioning for queries.  
  Test: `test/spatial_hash_test.dart`

## Rendering/Particles/Tweens
- [ ] **Particle component**  
  1. Lifetime, scale/alpha/color interpolation.  
  Files: `packages/engine_core/lib/src/rendering/particle.dart`

- [ ] **ParticleEmitter**  
  1. Emission rate/burst.  
  Files: `packages/engine_core/lib/src/rendering/particle_emitter.dart`

- [ ] **ParticleForces**  
  1. Forces affecting particles.  
  Files: `packages/engine_core/lib/src/rendering/particle_forces.dart`

- [ ] **ParticleSystem**  
  1. Spawns particles, ages them, removes expired.  
  Test: `test/particle_system_test.dart`

- [ ] **Tween**  
  1. Interpolates double value over duration.  
  Files: `packages/engine_core/lib/src/rendering/tween.dart`

- [ ] **TweenSystem**  
  1. Advances tweens, updates `.value`.  
  Test: `test/tween_system_test.dart`

- [ ] **DayNightCycle**  
  1. Time of day system.  
  Files: `packages/engine_core/lib/src/rendering/day_night_cycle.dart`

## AI Details
- [ ] **AIState component**  
  1. `behaviorId`, `memory` map.  
  Files: `packages/engine_core/lib/src/ai/ai_state.dart`

- [ ] **Behavior interface**  
  1. `Action decide(WorldView view, EntityId self)`.  
  Files: `packages/engine_core/lib/src/ecs/behavior.dart`

- [ ] **AISystem**  
  1. Resolves behavior from registry, calls decide, applies action.  
  Test: `test/ai_system_test.dart`

- [ ] **BehaviorRegistry**  
  1. Register/resolve/has behaviors by id.  
  Files: `packages/engine_core/lib/src/ecs/behavior.dart`

- [ ] **FleeBehavior**  
  1. Flees horizontally from target, optional minDistance/stopDistance/requireLineOfSight.  
  Test: `test/ai_system_test.dart` or dedicated

- [ ] **Steering**  
  1. seek/arrive/wander helpers.  
  Test: `test/doc_examples_ai_test.dart`

- [ ] **Hearing**  
  1. HearingComponent, HearingSystem processes SoundEvent.  
  Test: `test/doc_examples_ai_test.dart`

- [ ] **StateMachine**  
  1. FSM with states/transitions, JSON serialization.  
  Test: `test/doc_examples_ai_test.dart`

- [ ] **BehaviorTreeSystem**  
  1. Runs trees from `AIState.memory['_bt_root']`.  
  Test: `test/doc_examples_ai_test.dart`, `test/ai_system_test.dart`

- [ ] **All BT node types**  
  1. Verify Sequence, Selector, Parallel, Inverter, Repeater, Succeeder, Failer, Leaf, Wait, Cooldown, RandomSelector, RandomSequence, UntilSuccess, UntilFailure, Timeout, Throttle, Timer all implemented with toJson/fromJson.  
  Files: `packages/engine_core/lib/src/ai/behavior_tree.dart`

## WorldView (Agent API)
- [ ] **WorldView read-only**  
  1. Wraps World, no mutation methods exposed.  
  Files: `packages/engine_core/lib/src/ecs/world_view.dart`

- [ ] **WorldView.component<T>(self)**  
  1. Reads component from world.  
  Test: `test/world_view_test.dart`

- [ ] **WorldView.nearestWithPosition(x,y,exclude:self)**  
  1. Finds nearest entity with Position.  
  Test: `test/world_view_test.dart`

- [ ] **WorldView.entitiesWithAll<A,B>()**  
  1. Scans entities with both components.  
  Test: `test/world_view_test.dart`

- [ ] **WorldView.entitiesWithinRadius(x,y,radius,exclude:self)**  
  1. Finds nearby entities.  
  Test: `test/world_view_test.dart`

- [ ] **WorldView.hasLineOfSight(x,y,targetX,targetY)**  
  1. Checks line of sight (uses TileMap/raycast).  
  Test: `test/world_view_test.dart`

## Content & Level Loading
- [ ] **Level.loadInto(world,json)**  
  1. Spawns entities from plain JSON.  
  Test: `test/level_test.dart`

- [ ] **Level.validate(json)**  
  1. Shape validation, throws `LevelLoadException`.  
  Test: `test/level_validator_test.dart`

- [ ] **ComponentRegistry decoders**  
  1. Associates component names with JSON decoders.  
  Files: `packages/engine_core/lib/src/ecs/component_registry.dart`

- [ ] **LevelDocument/LevelFormat**  
  1. Structured level format.  
  Tests: `test/level_document_test.dart`, `test/level_format_test.dart`

- [ ] **LevelDiff**  
  1. Diff levels.  
  Files: `packages/engine_core/lib/src/content/level_diff.dart`

- [ ] **Prefab/Brush**  
  1. Prefabs and brush tools.  
  Files: `packages/engine_core/lib/src/content/prefab.dart`, `packages/engine_core/lib/src/content/brush.dart`

- [ ] **StringTable**  
  1. Localization with `{param}` substitution.  
  Test: `test/string_table_test.dart`

- [ ] **GameState**  
  1. Persists across scene changes.  
  Test: `test/game_state_test.dart`

- [ ] **Dialogue**  
  1. Dialogue system, DialogueGraph component.  
  Tests: `test/dialogue_test.dart`, `test/dialogue_compiler_test.dart`

- [ ] **Cinematic**  
  1. Cinematic system.  
  Files: `packages/engine_core/lib/src/content/cinematic.dart`

- [ ] **Inventory**  
  1. Inventory component/system.  
  Test: `test/inventory_test.dart`

- [ ] **SaveCodec/BigNumber/BigTreasury**  
  1. Save encoding, big numbers.  
  Tests: `test/save_codec_test.dart`, `test/big_number_test.dart`

- [ ] **Localization/NumberFormat/ActionAliases**  
  1. i18n and formatting.  
  Tests: `test/localization_test.dart`, `test/action_aliases_test.dart`

- [ ] **AnimationClipJson**  
  1. Animation clip serialization.  
  Test: `test/animation_clip_json_test.dart`

- [ ] **PlayerOptions**  
  1. Player settings.  
  Files: `packages/engine_core/lib/src/content/player_options.dart`

- [ ] **Analytics**  
  1. Analytics hooks.  
  Files: `packages/engine_core/lib/src/content/analytics.dart`

- [ ] **ModifierStack/CostCurve**  
  1. Modifiers and cost curves.  
  Files: `packages/engine_core/lib/src/content/modifier_stack.dart`, `packages/engine_core/lib/src/content/cost_curve.dart`

- [ ] **OfflineProgress**  
  1. Offline progress calculation.  
  Files: `packages/engine_core/lib/src/content/offline_progress.dart`

## Turn-Based Strategy
- [ ] **TurnState/Team/ActionPoints**  
  1. Turn management components.  
  Files: `packages/engine_core/lib/src/turn/turn_components.dart`

- [ ] **startTurnBasedGame/endTurn/trySpendActionPoints**  
  1. Turn flow helpers.  
  Files: `packages/engine_core/lib/src/turn/turn_system.dart`

- [ ] **Order/MoveOrder/AttackOrder**  
  1. JSON serializable orders.  
  Files: `packages/engine_core/lib/src/turn/order.dart`

- [ ] **OrderQueue/submitOrder/OrderSystem**  
  1. Order queuing and execution.  
  Files: `packages/engine_core/lib/src/turn/order_system.dart`

- [ ] **GridPosition/GridFootprint**  
  1. Grid-based positioning.  
  Files: `packages/engine_core/lib/src/turn/turn_components.dart`

- [ ] **GridNavigator/flow field**  
  1. Weighted 8-way A*, reachable sets, flow fields.  
  Files: `packages/engine_core/lib/src/turn/grid_navigation.dart`, `packages/engine_core/lib/src/turn/flow_field.dart`

- [ ] **Formation**  
  1. Unit formations.  
  Files: `packages/engine_core/lib/src/turn/formation.dart`

- [ ] **Economy/Producer/Treasury/BigTreasury**  
  1. Resource economy.  
  Tests: `test/economy_test.dart`

- [ ] **Gathering/ResourceNode/Depot/Gatherer**  
  1. Resource gathering.  
  Test: `test/gathering_test.dart`

- [ ] **Construction/BuildWorker/Construction**  
  1. Building construction.  
  Test: `test/gathering_test.dart`

- [ ] **Tech/TechState**  
  1. Technology tree.  
  Files: `packages/engine_core/lib/src/turn/tech.dart`

- [ ] **Combat/UnitStats/AttackProfile/StatusEffects/installCombat/WinConditionSystem**  
  1. Combat resolution.  
  Files: `packages/engine_core/lib/src/turn/combat.dart`, `packages/engine_core/lib/src/turn/status.dart`, `packages/engine_core/lib/src/turn/objectives.dart`

- [ ] **Vision/FogOfWar/VisionSystem/canSee**  
  1. Line of sight and fog of war.  
  Files: `packages/engine_core/lib/src/turn/fog_of_war.dart`

- [ ] **Selection/selectAtCell/selectInBox/commandSelected**  
  1. Unit selection.  
  Files: `packages/engine_core/lib/src/turn/selection.dart`

- [ ] **TurnAI/AggressiveAI/AITurnSystem**  
  1. AI for turn-based games.  
  Test: `test/ai_turn_test.dart`

- [ ] **Realtime/RealtimeStats**  
  1. Real-time strategy elements.  
  Files: `packages/engine_core/lib/src/turn/realtime.dart`
  Test: `test/realtime_test.dart`

- [ ] **Occupancy/Footprint**  
  1. Grid occupancy.  
  Files: `packages/engine_core/lib/src/turn/occupancy.dart`, `packages/engine_core/lib/src/turn/footprint.dart`

- [ ] **Carry**  
  1. Carrying mechanics.  
  Files: `packages/engine_core/lib/src/turn/carry.dart`

## UI Components (Core)
- [ ] **Button/ButtonHitBox/ButtonHitTest**  
  1. UI button components.  
  Files: `packages/engine_core/lib/src/ui/button.dart`, `packages/engine_core/lib/src/ui/button_hit_box.dart`, `packages/engine_core/lib/src/ui/button_hit_test.dart`

- [ ] **TriggerZone/TriggerHelpers**  
  1. Trigger zones.  
  Files: `packages/engine_core/lib/src/ui/trigger_zone.dart`, `packages/engine_core/lib/src/ui/trigger_helpers.dart`

- [ ] **RoomExit**  
  1. Room transitions.  
  Files: `packages/engine_core/lib/src/ui/room_exit.dart`

## Networking
- [ ] **NetFrame/NetEndpoint**  
  1. Networking primitives.  
  Files: `packages/engine_core/lib/src/net/net_frame.dart`, `packages/engine_core/lib/src/net/net_endpoint.dart`

- [ ] **WorldSnapshot/StateSync**  
  1. World snapshots for networking.  
  Files: `packages/engine_core/lib/src/net/world_snapshot.dart`, `packages/engine_core/lib/src/net/state_sync.dart`

- [ ] **Lobby/Session**  
  1. Lobby and session management.  
  Files: `packages/engine_core/lib/src/net/lobby.dart`, `packages/engine_core/lib/src/net/session.dart`

- [ ] **RollbackSession/LagCompensation**  
  1. Rollback netcode.  
  Files: `packages/engine_core/lib/src/net/rollback_session.dart`, `packages/engine_core/lib/src/net/lag_compensation.dart`

- [ ] **LoopbackLink/UDPTransport**  
  1. Transport implementations.  
  Files: `packages/engine_core/lib/src/net/loopback_link.dart`, `packages/engine_core/lib/src/net/udp_transport.dart`

- [ ] **Net frame tests**  
  1. Test networking.  
  Test: `test/net_frame_test.dart`

## Graph System
- [ ] **Graph/NodeKind**  
  1. Visual scripting graph.  
  Files: `packages/engine_core/lib/src/graph/graph.dart`, `packages/engine_core/lib/src/graph/node_kind.dart`

- [ ] **GraphValidator**  
  1. Validate graphs.  
  Files: `packages/engine_core/lib/src/graph/graph_validator.dart`

- [ ] **DialogueCompiler**  
  1. Compile dialogue graphs.  
  Files: `packages/engine_core/lib/src/graph/dialogue_compiler.dart`

- [ ] **BehaviorTreeGraph**  
  1. BT graph representation.  
  Files: `packages/engine_core/lib/src/graph/behavior_tree_graph.dart`

## Commands/Editor Tools
- [ ] **Command/CommandHistory**  
  1. Undo/redo system.  
  Files: `packages/engine_core/lib/src/command/command_history.dart`, `packages/engine_core/lib/src/command/edit_command.dart`

- [ ] **EntityCommands/TileCommands/PrefabCommands/CompositeCommand**  
  1. Editor commands.  
  Files: `packages/engine_core/lib/src/command/entity_commands.dart`, `packages/engine_core/lib/src/command/tile_commands.dart`, `packages/engine_core/lib/src/command/prefab_commands.dart`, `packages/engine_core/lib/src/command/composite_command.dart`

## Validation & IO
- [ ] **LevelValidator/Reachability**  
  1. Level validation.  
  Tests: `test/level_validator_test.dart`

- [ ] **AtomicSave/FileLock**  
  1. Safe file I/O.  
  Files: `packages/engine_core/lib/src/io/atomic_save.dart`, `packages/engine_core/lib/src/io/file_lock.dart`

## Distribution
- [ ] **ReleaseManifest**  
  1. Release manifest with Ed25519 signatures.  
  Files: `packages/engine_core/lib/src/distribution/release_manifest.dart`

## Other Packages
- [ ] **engine_schema**  
  1. Schemas package present and used.  
  Files: `packages/engine_schema/`

- [ ] **engine_platformer**  
  1. Platformer-specific systems (TileCollisionSystem cares about PlatformerController.grounded).  
  Files: `packages/engine_platformer/`

- [ ] **engine_strategy**  
  1. Strategy-specific code.  
  Files: `packages/engine_strategy/`

- [ ] **engine_flutter**  
  1. Flutter integration, SaveGame builds on World.toJson().  
  Files: `packages/engine_flutter/`

- [ ] **engine_idle**  
  1. Idle game systems.  
  Files: `packages/engine_idle/`

- [ ] **engine_api/engine_cli/engine_studio**  
  1. API/CLI/studio tools.  
  Files: `packages/engine_api/`, `packages/engine_cli/`, `packages/engine_studio/`

## Testing Deep Dive
- [ ] **All tests pass**  
  1. `dart test` in engine_core shows all passed.  
  Current: 1300+ tests passing.

- [ ] **Key test files exist**  
  1. Verify presence of major test files (world, components, systems, ai, turn, content, net, etc.).  
  Files: `packages/engine_core/test/*.dart`

- [ ] **Doc example tests**  
  1. `test/doc_examples_ai_test.dart`, `test/doc_examples_performance_test.dart`.  
  Ensure docs can't drift.

- [ ] **Event helpers tested**  
  1. `test/event_helpers_test.dart`.  
  Covers onCollisionBetween/Involving/WithAny.

- [ ] **Component store tested**  
  1. `test/component_store_test.dart`.

- [ ] **Deterministic random tested**  
  1. `test/deterministic_random_test.dart`.

## Benchmarks
- [ ] **World step benchmark**  
  1. `benchmark/world_step_benchmark.dart` runs.  
  Files: `packages/engine_core/benchmark/world_step_benchmark.dart`

- [ ] **Collision system benchmark**  
  1. `benchmark/collision_system_benchmark.dart` runs.

- [ ] **Particle system benchmark**  
  1. `benchmark/particle_system_benchmark.dart` runs.

- [ ] **Entity churn benchmark**  
  1. `benchmark/entity_churn_benchmark.dart` runs.

## Analysis & Linting
- [ ] **dart analyze --fatal-infos clean**  
  1. No issues.  
  Config: `analysis_options.yaml`

- [ ] **lints package used**  
  1. `dev_dependencies: lints: ^5.0.0`

## Build/Tooling
- [ ] **tool/gen_bundled_docs.dart exists**  
  1. Doc generation tool.  
  Files: `packages/engine_core/tool/gen_bundled_docs.dart`

- [ ] **coverage_integration present**  
  1. Coverage data exists.  
  Files: `packages/engine_core/coverage_integration/lcov.info`

## Final Verification
- [ ] **Full engine_core verification**  
  1. From `packages/engine_core`: `dart pub get --offline && dart analyze --fatal-infos && dart test` all pass.  
  2. Document results.

- [ ] **Check exports are complete**  
  1. Verify `lib/engine_core.dart` exports all public APIs used by checklist.  
  2. Spot check a few key exports.

- [ ] **Follow dependency direction**  
  1. engine_core has no Flutter imports.  
  2. engine_platformer depends on core/flutter as appropriate.  
  3. engine_flutter integrates with core.

- [ ] **Preserve working tree**  
  1. Only change engine code as needed.  
  2. Don't touch gitignored paths.

- [ ] **Update docs if APIs change**  
  1. Update package READMEs if public API changes.  
  2. Update CHANGELOG.md if shipped changes.
