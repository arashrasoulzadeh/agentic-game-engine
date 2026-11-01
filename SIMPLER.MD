# SIMPLER

Goal: Refactor the engine to be smarter and easier for game developers to write games with less boilerplate, fewer footguns, and clearer APIs. 

Focus on DX over coverage of every internal type.

## Quick Start DX
- [ ] **One-line world setup**: Add a helper like `Game.create(width: ..., height: ...)` that auto-calls `registerCoreComponents(world)` and sets up sensible defaults.
- [ ] **System presets**: Add `installCoreSystems(world)`, `installPlatformerSystems(world)`, `installTopdownSystems(world)`, `installTurnBasedSystems(world)`. Bundle common systems in the right order instead of manually adding them one by one.
- [ ] **Entity builder**: Allow `world.spawn()` to be fluent (`world.spawn()..with(Position(0,0))..with(Velocity(10,0))`) or add `world.create([Position(...), Velocity(...), ...])` to create an entity with components in one call.
- [ ] **Sensible defaults**: Give common components (like `Collider`) reasonable defaults so new devs don't have to guess values.

## Smarter Core API
- [ ] **Shortcuts on World**: Add `world.get<T>(id)`, `world.set<T>(id, comp)`, `world.has<T>(id)`, `world.remove<T>(id)`. Hide `storeOf<T>()` behind these cleaner helpers.
- [ ] **Unified entity API**: Let devs work with entities without needing to juggle raw `EntityId` + stores constantly.
- [ ] **Event sugar**: Simplify `World.events` usage. Add helpers like `world.onCollision((a,b)=>...)`, `world.on<T>((e)=>...)` to avoid verbose boilerplate.
- [ ] **Step wrapper**: Consider `game.update(dt)` as a higher level than calling `world.step(dt)` directly.
- [ ] **Easier serialization**: Simplify `toJson()/applyPatch()` into a cleaner `game.save()` / `game.load()` flow.

## Components & Registration
- [ ] **Less registration boilerplate**: Reduce the need to manually register every custom component. Explore codegen or a simpler registration path.
- [ ] **Convention over config**: If a component follows a simple `toJson/fromJson` pattern, allow auto-registration.
- [ ] **Smarter schemas**: Only require schemas where actually needed. Don't force them for every single component.
- [ ] **Cleaner `registerCoreComponents`**: Keep it but make room for user components to be registered more ergonomically.

## Systems
- [ ] **System groups**: Allow grouping related systems (`SystemGroup`) and adding them in one go.
- [ ] **Auto ordering**: Prevent common footguns like adding `CollisionSystem` before `MovementSystem`. Either enforce ordering, warn, or have presets handle it.
- [ ] **Lifecycle hooks**: Consider `onStart`, `onStop` on systems for cleaner setup/teardown.
- [ ] **Fewer global systems**: Make optional systems truly optional and easy to opt-in/out of.

## AI, Behaviors & Behavior Trees
- [ ] **Fluent BT API**: Replace verbose `BTSequence(children: [...])` nesting with a readable DSL like `BT.seq([BT.leaf('idle'), BT.wait(1)])` or builder pattern.
- [ ] **BT helpers**: Add shortcuts for common patterns (`BT.ifThen`, `BT.whileRunning`, `BT.repeatForever`) to cut down on nesting.
- [ ] **Simpler Behavior creation**: Make it easier to write inline behaviors without needing to create full classes for trivial ones (closures/functions where reasonable).
- [ ] **Smarter AIState**: Hide `_bt_root`, `_bt_blackboard` keys behind helpers like `ai.setTree(tree)`, `ai.getBlackboard()`.
- [ ] **WorldView ergonomics**: Keep it read-only but add more practical query helpers for common game logic.

## Levels, Prefabs & Content
- [ ] **One-liner loading**: `Level.loadInto(world, 'assets/level.json')` or support loading from assets directly.
- [ ] **Prefab API**: Make spawning prefabs dead simple (`world.spawnPrefab('enemy', x: 10, y: 20)`) with sensible defaults.
- [ ] **Safer validation errors**: `Level.validate` throws `LevelLoadException` but errors should be human-readable and point to the exact fix.
- [ ] **Data-driven without boilerplate**: Let developers focus on level data, not wiring up every component type.
- [ ] **Component defaults on load**: Apply sensible defaults when spawning from level JSON to avoid "missing required component" errors.

## Turn-Based & Strategy
- [ ] **Game mode factory**: Add `TurnBasedGame.create(world, config: ...)` to wire up turn state, orders, selection, combat, vision in one call.
- [ ] **Unified commands**: Simplify issuing orders. Instead of manually building `MoveOrder` objects everywhere, add `unit.moveTo(x,y)`, `unit.attack(target)`.
- [ ] **Selection helpers**: Make selecting units and issuing commands feel natural for RTS-style games.
- [ ] **Less ceremony**: Hide grid/footprint/order queue plumbing behind higher level APIs where possible.

## UI, Input & Integration
- [ ] **Input abstraction**: Consider a simple `Input` helper on `World`/`Game` to avoid reaching into platform-specific details.
- [ ] **Trigger helpers**: Make `TriggerZone` easier to use with callbacks.
- [ ] **Button API**: Simplify hit testing and wiring up buttons.
- [ ] **Flutter integration polish**: Make `engine_flutter` integration feel natural with minimal glue code.


## Component-Centric API (Component, not Store)
- [ ] **Everything is a component**: Don't think in terms of "stores of components". Think in terms of components attached to entities. 
- [ ] **No "Store" in public API**: Avoid `storeOf`, `Store`, "key", or "name" when referring to component access. Use component-centric terminology everywhere.
- [ ] **Use component accessors**: Prefer `getComponent<T>(id)`, `setComponent<T>(id, value)`, `hasComponent<T>(id)`, `removeComponent<T>(id)`. Use `world.component<T>()` or `world.components<T>()` to access component containers.
- [ ] **Migrate as you go**: When touching any code during refactor, replace `storeOf<T>()` with the component-centric equivalents. Don't introduce new `store`-based APIs.
- [ ] **Keep implementation detail hidden**: If `ComponentStore` remains internally, don't let "Store" leak into public-facing method names, comments, or docs.
- [ ] **Fluent entity access**: Where possible, allow working with components directly on entity handles (`entity.get<T>()`, `entity.set<T>()`, `entity.has<T>()`).

## General Cleanup
- [ ] **Barrel exports**: Clean up `engine_core.dart` so common imports are minimal (`import 'package:engine_core/engine_core.dart';` should cover most game code).
- [ ] **Consistent naming**: Unify naming across similar APIs (e.g. `addSystem` vs others).
- [ ] **Smarter errors**: Replace cryptic errors with actionable messages (especially registry lookups, missing components).
- [ ] **Remove dead APIs**: Deprecate or remove confusing/unused APIs that add complexity.
- [ ] **Stronger type safety**: Leverage Dart's type system to prevent common mistakes at compile time.
- [ ] **Docs for common flows**: Make the "happy path" obvious (spawn entity, add system, run loop) with minimal steps.
- [ ] **Keep core pure**: Don't leak Flutter into `engine_core`. Keep boundaries clean.

## Validation
- [ ] **Refactor doesn't break existing tests**: All `dart test` must still pass after changes.
- [ ] **New APIs have tests**: Add tests for any new ergonomic helpers introduced.
- [ ] **Analyze stays clean**: `dart analyze --fatal-infos` must pass.
- [ ] **Try writing a tiny game**: Sanity check by writing a minimal topdown/platformer using the new simplified APIs to ensure it's actually nicer.
