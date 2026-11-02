# SIMPLER

Goal: Refactor the engine to be smarter and easier for game developers to write games with less boilerplate, fewer footguns, and clearer APIs.

Focus on DX over coverage of every internal type. Every change must keep `dart analyze --fatal-infos` clean and all tests passing.

## Philosophy
- [ ] **Components only**: Everything attachable to entities is a component. Never speak of "stores" in public API. Think in `getComponent/setComponent/hasComponent/removeComponent`.
- [ ] **Convention over configuration**: Sensible defaults everywhere. A minimal game should work with < 20 lines of code.
- [ ] **Explicit over magic**: When magic is used, it's discoverable and documented. No hidden global state.
- [ ] **Pure core**: `engine_core` stays Flutter-free. All platform integration goes in `engine_flutter`.
- [ ] **Data-driven friendly**: JSON/level data should be easy to load and spawn without manual wiring for every type.

## Quick Start DX
- [ ] **Game facade**: Add `Game` class in `engine_core` with `Game.create(width, height, {systems})` that auto-registers components, adds sensible system presets, and exposes `world`, `update(dt)`, `spawn()`, etc.
- [ ] **Auto-register on demand**: Allow components to self-register or auto-register when first used. Eliminate the need to manually call `registerCoreComponents` in most cases.
- [ ] **System presets**: Add `SystemPresets.core(world)`, `SystemPresets.platformer(world)`, `SystemPresets.topdown(world)`, `SystemPresets.turnBased(world)`, `SystemPresets.idle(world)`. Each adds systems in correct dependency order with one call.
- [ ] **Entity factory**: Add `world.entity()` returning a fluent builder, or `world.spawnWith([Component1(...), Component2(...)])`. Support `..add()`, `..withX()`, chaining.
- [ ] **Spawn shortcuts**: `world.spawnAt(x,y)` creates entity with `Position(x,y)`. `world.spawnSprite(...)`, `world.spawnBody(...)` for common patterns.
- [ ] **Minimal hello-world**: Test that a bouncing sprite can be made in < 15 lines with new API.

## Component-Centric API (No "Store" Leaks)
- [ ] **Rename conceptually**: In all public APIs, comments, docs, errors - use "component" not "store". `ComponentStore` can remain as internal impl but never exposed as "Store API".
- [ ] **World component access**: Add `world.getComponent<T>(id)`, `world.setComponent<T>(id, T value)`, `world.hasComponent<T>(id)`, `world.removeComponent<T>(id)`. Add `world.component<T>(id)` as shorthand returning nullable.
- [ ] **Entity handle**: Create lightweight `Entity` or `EntityRef` with `get<T>()`, `set<T>(v)`, `has<T>()`, `remove<T>()`, `destroy()`. Pass these around instead of raw ints where ergonomic.
- [ ] **Component container access**: `world.components<T>()` returns the component collection for iteration/querying. `world.allComponents<T>()` for dense iteration.
- [ ] **Query helpers**: Add `world.query<T>()`, `world.query2<A,B>()`, `world.query3<A,B,C>()` returning iterators/tuples. Hide archetype complexity.
- [ ] **Migrate incrementally**: Replace `storeOf<T>()` with component-centric APIs on every file touched. Don't add new `storeOf` usages.
- [ ] **Deprecation path**: Mark `storeOf` deprecated with clear migration message pointing to component APIs.

## Smarter World API
- [ ] **Shortcuts**: `world.get<T>(id)`, `world.set<T>(id, T)`, `world.has<T>(id)`, `world.del<T>(id)` as ultra-short aliases.
- [ ] **Batch operations**: Support setting/removing multiple components efficiently.
- [ ] **Event sugar**: `world.on<E>((e) => {})`, `world.onCollision((a,b,e) => {})`, `world.once<E>((e)=>{})`. Auto-unsubscribe helpers.
- [ ] **Update wrapper**: `world.update(dt)` as alias to `step(dt)` with clearer naming for game devs.
- [ ] **Lifecycle**: `world.start()`, `world.pause()`, `world.stop()` helpers for game loops.
- [ ] **Save/Load**: `world.save()` returning `Map<String,dynamic>`, `world.load(data)` as cleaner than raw `toJson/applyPatch`.
- [ ] **Dispose properly**: Ensure all resources cleaned up, job system shut down.

## Entity & Component Ergonomics
- [ ] **Fluent API everywhere**: `world.spawn().at(10,20).with(Velocity(5,0)).with(Collider(8))`.
- [ ] **Component defaults**: Allow components to have `static const defaults` or builder constructors. `Collider()` with sensible radius.
- [ ] **Attach/detach**: `entity.add<Component>(value)`, `entity.remove<Component>()` clear and chainable.
- [ ] **Optional components**: Make missing components return null gracefully, avoid crashes.
- [ ] **Tags as components**: Simple marker components should be trivial to add/remove.
- [ ] **Component pools**: Consider pooling for high-churn components (particles) to reduce allocations.

## Systems Refactor
- [ ] **System ordering enforced**: Core dependencies (Movement before Collision) enforced or auto-sorted.
- [ ] **System groups**: `SystemGroup([sys1, sys2])` can be added as one unit.
- [ ] **Phase-based systems**: `updatePhase` (prePhysics, physics, postPhysics, late) for better organization.
- [ ] **Conditional systems**: Enable/disable systems easily without removing them.
- [ ] **System context**: Pass `dt`, `world` cleanly. Consider `System.update(context)`.
- [ ] **ECS queries built-in**: Systems can declare queries (`query of: [Position, Velocity]`) and iterate efficiently.
- [ ] **Less boilerplate**: Function-based systems or mixins to reduce class ceremony.

## AI, Behavior Trees & State Machines
- [ ] **Fluent BT DSL**: `BT.sequence([BT.ifHasTarget(...), BT.chase(), BT.wait(0.5)])` much cleaner than deep nesting.
- [ ] **BT node factories**: `BT.leaf('idle')`, `BT.selector([...])`, `BT.repeat(n, child)`, `BT.forever(child)`.
- [ ] **Inline behaviors**: `Behavior((view, self) => MoveAction(...))` for trivial cases without full classes.
- [ ] **BT helpers**: `BT.inRange(radius, child)`, `BT.seeTarget(child)`, `BT.random([children])`, `BT.cooldown(sec, child)`.
- [ ] **AI helpers**: `ai.setBehavior('chase')`, `ai.runTree(root)`, hide memory keys.
- [ ] **Blackboard sugar**: `blackboard.get/set/has/inc` with type safety.
- [ ] **Steering made easy**: `Steer.seek(arrive(wander(...)))` composable.
- [ ] **State machine DSL**: Cleaner JSON or builder API.

## Levels, Prefabs & Assets
- [ ] **Asset loading**: Integrate with Flutter/assets or simple file loading. `Level.fromAsset('levels/1.json')`.
- [ ] **Prefab registry**: `PrefabRegistry` with `register('enemy', {...})`, `spawn('enemy', pos)`.
- [ ] **Auto-spawn from prefab**: Attach `PrefabRef` component and have system spawn it, or just call directly.
- [ ] **Component defaults on spawn**: Level loader fills missing defaults intelligently.
- [ ] **Validation with fixes**: Errors say "missing Position on entity 'player', add {\"type\":\"position\",\"x\":0,\"y\":0}".
- [ ] **Tiled integration smoother**: Easier mapping from Tiled objects/tiles to components/prefabs.
- [ ] **Hot reload friendly**: Level/prefab changes easy to reload in dev.

## Physics, Collision & Movement
- [ ] **Simple movement**: `Movement.move(entity, dir * speed * dt)` helpers.
- [ ] **Collision callbacks**: Easier to react to collisions without manual event wiring.
- [ ] **Tilemap helpers**: `tilemap.isSolid(x,y)`, `tilemap.getTile(x,y)` with world/tile coords conversion.
- [ ] **Raycast API**: Simpler `world.raycast(from, to)` returning hits.
- [ ] **Spatial queries**: `world.findNear(pos, radius)` returns entities/components easily.

## Turn-Based Simplification
- [ ] **One-call setup**: `TurnGame.setup(world)` wires everything.
- [ ] **Action API**: `unit.do(MoveTo(x,y))`, `unit.do(Attack(target))` queued automatically.
- [ ] **Turn flow**: `game.nextTurn()`, `game.endPlayerTurn()` with callbacks.
- [ ] **Selection**: `game.select(entity)`, `game.selectAll([ids])`, `game.commandSelected(action)`.
- [ ] **AI turns**: Opt-in, simple to customize.

## Input & UI
- [ ] **Input manager**: `Input.isPressed(Key.up)`, `Input.getAxis()`, unified across platforms.
- [ ] **Action mapping**: Bind keys/buttons to game actions.
- [ ] **UI helpers**: Simpler button/trigger wiring with callbacks.
- [ ] **Camera helpers**: Follow target, bounds, shake.

## Error Messages & Debugging
- [ ] **Actionable errors**: Every "component not found" says how to fix it.
- [ ] **Type-aware errors**: When wrong type passed, show expected vs got clearly.
- [ ] **Dev mode warnings**: Warn about common mistakes (system order, missing registration) in debug.
- [ ] **World inspector helpers**: `world.debug()` prints entity/component summary.
- [ ] **Assertions**: Helpful asserts in debug, stripped in release.

## API Surface Cleanup
- [ ] **Barrel exports minimal**: `engine_core.dart` exports only what game devs need. Move advanced/internal to subpaths.
- [ ] **Consistent naming**: Pick one style and apply everywhere (camelCase methods, clear names).
- [ ] **Remove redundancy**: Eliminate duplicate/confusing APIs.
- [ ] **Type inference friendly**: APIs should work well with Dart's inference.
- [ ] **Extension methods**: Use extensions to add ergonomics without bloating classes.
- [ ] **Documentation**: Every public API has clear dartdoc with examples.

## Performance Without Complexity
- [ ] **Query optimization**: Archetype queries fast but hidden behind simple API.
- [ ] **Avoid allocations in hot paths**: Where possible, but don't sacrifice DX.
- [ ] **Pooling helpers**: Easy to pool objects/components.
- [ ] **Profiling optional**: `WorldProfiler` exists but not required.

## Migration Strategy
- [ ] **Backward compatible first**: Add new APIs, deprecate old ones gradually.
- [ ] **Touch files to migrate**: When editing, migrate `storeOf` -> component APIs.
- [ ] **Tests guide migration**: Keep all tests green, update them to nicer APIs over time.
- [ ] **Incremental**: Don't big-bang rewrite. Improve API surface piece by piece.

## Validation
- [ ] **All tests pass**: `cd packages/engine_core && dart test` after every major change.
- [ ] **Analyze clean**: `dart analyze --fatal-infos` always green.
- [ ] **Tiny game test**: Write a minimal platformer/topdown using new APIs - if it's clumsy, simplify more.
- [ ] **Flutter still works**: Check `packages/engine_flutter` compiles if touched.
- [ ] **No core Flutter deps**: `grep -r "flutter" packages/engine_core/lib` returns nothing.
