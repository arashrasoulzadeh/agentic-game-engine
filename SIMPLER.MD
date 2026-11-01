# SIMPLER

One-by-one checklist for engine code only (`packages/engine_core`, `packages/engine_schema`, `packages/engine_platformer`, `packages/engine_strategy`, `packages/engine_flutter`, `packages/engine_idle`, `packages/engine_api`, `packages/engine_cli`, `packages/engine_studio`). Skip gitignored (`test_game/`, `examples/`, `zahaak/`, `mobarez/`).

## Setup
- [ ] `cd packages/engine_core && dart pub get --offline` (ensure `engine_schema` via `pubspec_overrides.yaml`)
- [ ] `dart analyze --fatal-infos` passes
- [ ] `dart test` passes
- [ ] `dart pub global run coverage:test_with_coverage` gives 100% line coverage

## Core
- [ ] `registerCoreComponents(world)` registers all built-ins
- [ ] `World(width,height)`: `spawn()`, `destroy(id)`, `storeOf<T>()`, `addSystem()`, `step(dt)`, `toJson()`, `applyPatch()`, `events`, `tick`
- [ ] Systems: `MovementSystem`, `CollisionSystem`, `ParticleSystem`, `TweenSystem`, `PushableSystem`, `TileAnimationSystem`, `HearingSystem`, `BehaviorTreeSystem`, `AISystem`, `StateMachineSystem`
- [ ] Events: `events.on<T>()` + flush on `step()`; `onCollisionBetween/Involving/WithAny`

## Components
- [ ] Core: `Position`, `Velocity`, `Collider`, `TileMap`, `AIState`, `Particle`, `ParticleEmitter`, `ParticleForces`, `Tween`, `Pushable`, `Button`, `ButtonHitBox`, `TriggerZone`, `RoomExit`, `HearingComponent`, `SoundEvent`

## AI & Behavior Trees
- [ ] `Behavior` interface + `BehaviorRegistry` + `Action` (including `NoOpAction`, `FailureAction`)
- [ ] `WorldView` read-only: `component<T>()`, `nearestWithPosition()`, `entitiesWithAll<A,B>()`, `entitiesWithinRadius()`, `hasLineOfSight()`
- [ ] `FleeBehavior`, steering (`seek`, `arrive`, `wander`), hearing
- [ ] BT: `BTSequence`, `BTSelector`, `BTParallel`, `BTInverter`, `BTRepeater`, `BTSucceeder`, `BTFailer`, `BTLeaf`, `BTWait`, `BTCooldown`, `BTRandomSelector`, `BTRandomSequence`, `BTUntilSuccess`, `BTUntilFailure`, `BTTimeout`, `BTThrottle`, `BTTimer` (all serializable)
- [ ] State machine: JSON states/transitions with named conditions

## Physics, Pathfinding & Spatial
- [ ] `findPath(tileMap, mapOrigin, fromX, fromY, toX, toY)` (A*)
- [ ] `raycastTileMap(...)`
- [ ] `SpatialHash`
- [ ] `Autotile`, `TMX` import/export, procedural generation

## Content & Levels
- [ ] `Level.loadInto(world, json)`, `Level.validate(json)` (throws `LevelLoadException`)
- [ ] `ComponentRegistry` with JSON decoders/schemas
- [ ] `LevelDocument`, `LevelFormat`, `LevelDiff`, `Prefab`, `Brush`
- [ ] `StringTable` with `{param}` substitution
- [ ] `GameState`, `Dialogue`/`DialogueGraph`, `Cinematic`, `Inventory`
- [ ] `SaveCodec`, `BigNumber`, `BigTreasury`, `Localization`, `NumberFormat`, `ActionAliases`, `AnimationClipJson`, `PlayerOptions`, `Analytics`, `ModifierStack`, `CostCurve`, `OfflineProgress`

## Turn-Based Strategy
- [ ] `TurnState`, `Team`, `ActionPoints`, `startTurnBasedGame()`, `endTurn()`, `trySpendActionPoints()`
- [ ] Orders: `MoveOrder`, `AttackOrder`, `OrderQueue`, `submitOrder()`, `OrderSystem`
- [ ] Grid: `GridPosition`, `GridFootprint`, `GridNavigator` (weighted 8-way A*, `reachable`), `flow_field`, `formation`, `occupancy`
- [ ] Economy: `Treasury`, `BigTreasury`, `Producer`, `ResourceNode`, `Depot`, `Gatherer`, `BuildWorker`, `Construction`
- [ ] Combat: `UnitStats`, `AttackProfile`, `StatusEffects`, `installCombat()`, `WinConditionSystem`, `objectives`
- [ ] Vision/Fog: `Vision`, `FogOfWar`, `VisionSystem`, `canSee()`
- [ ] Selection: `Selected`, `selectAtCell()`, `selectInBox()`, `commandSelected()`
- [ ] AI: `TurnAI`, `AggressiveAI`, `AITurnSystem`
- [ ] Tech: `TechState`, `Provides`
- [ ] Realtime/Carry

## Networking, Graphs, Commands, Validation
- [ ] Net: `NetFrame`, `NetEndpoint`, `WorldSnapshot`, `StateSync`, `Lobby`, `Session`, `RollbackSession`, `LagCompensation`, `LoopbackLink`, `UDPTransport`
- [ ] Graphs: `Graph`, `NodeKind`, `GraphValidator`, `DialogueCompiler`, `BehaviorTreeGraph`
- [ ] Commands: `CommandHistory`, `EditCommand`, `EntityCommands`, `TileCommands`, `PrefabCommands`, `CompositeCommand`
- [ ] Validation/IO: `LevelValidator`, `Reachability`, `AtomicSave`, `FileLock`, `ReleaseManifest`

## ECS Internals
- [ ] `EntityManager`, `ComponentStore<T>`, `ComponentRegistry`, `ArchetypeManager`
- [ ] `System` interface, `JobSystem`, `WorldProfiler`, `DeterministicRandom`, `ReplayRecorder`, `RingBuffer`
- [ ] `Action` system, `WorldView`

## Packages
- [ ] `engine_schema` present/used
- [ ] `engine_platformer` (platformer-specific systems)
- [ ] `engine_strategy` 
- [ ] `engine_flutter` (SaveGame on `World.toJson()`)
- [ ] `engine_idle`, `engine_api`, `engine_cli`, `engine_studio`

## Tests, Benchmarks & Quality
- [ ] All tests pass (`dart test`)
- [ ] Key tests: world, components, systems, AI, turn, content, net, events, determinism
- [ ] Doc tests pass (`doc_examples_ai_test.dart`, `doc_examples_performance_test.dart`)
- [ ] Benchmarks run: `world_step_benchmark`, `collision_system_benchmark`, `particle_system_benchmark`, `entity_churn_benchmark`
- [ ] `dart analyze --fatal-infos` clean
- [ ] 100% line coverage

## Final Checks
- [ ] `engine_core` has no Flutter imports
- [ ] Dependency direction respected
- [ ] Exports in `lib/engine_core.dart` complete
- [ ] Only engine code changed, gitignored untouched
- [ ] Update READMEs/CHANGELOG if APIs change
