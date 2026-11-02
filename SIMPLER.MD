# SIMPLER

Goal: Refactor the engine to be smarter and easier for game developers to write games with less boilerplate, fewer footguns, and clearer APIs.

Focus on DX over coverage of every internal type. Every change must keep `dart analyze --fatal-infos` clean and all tests passing.

## HOW TO USE THIS FILE (read first)
The phased plan below is the **executable** part. Everything after "Backlog reference" is the unphased idea list the phases draw from. Do steps strictly in order; a step may start only when every earlier step in its phase is committed and its gate is green. Items marked **DECISION** need the owner's answer first; do not guess.

### Agent protocol
1. One step = one commit. Never batch steps. Commit only when its gate is green (CLAUDE.md allows commit+push per completed TODO item).
2. Before editing: re-read the files you will touch (they change). Check `git status`; do not mix your work with unrelated uncommitted changes.
3. Every step ships: code, doc comments on every new public member (the *why*), and a test that **fails without the change** (verify by running it against the pre-change code or by reasoning in the commit message). Bug fix = regression test.
4. Backward compatible first: add new API, mark old `@Deprecated('use X')`, never delete in the same step as the replacement.
5. If a gate fails, fix forward in the same step or `git restore` the step's files. Never weaken or delete an existing test to get green; never commit red.
6. Never un-gitignore `test_game/`; never add a sample app. Keep `engine_core` Flutter-free; respect the DAG `engine_core -> engine_flutter -> engine_platformer` (genre-general data in core, genre logic in the genre package).
7. New component => register in the right `register*Components` with `toJson/fromJson` + schema. New operation => follow the add-operation checklist in `TODO.md` (agent-API section), add the 1:1 `game_agent` command, regenerate `docs/reference/operations.md`.
8. Doc edits that feed bundled docs => regenerate with `cd packages/engine_core && dart run tool/gen_bundled_docs.dart`.
9. Commit message: explain *why* (what broke / how found / why fix works), end with the attribution line the session was given.
10. Stop and ask the owner when: a DECISION is unresolved, a step needs a backward dependency, a benchmark regresses past the threshold, or a gate is red for a reason outside the step.

### Environment (this machine)
- `export PATH="$PATH:/Users/arashrasoulzadeh/develop/flutter/bin"`; pub.dev is unreachable: use `--no-pub`/`--offline`.
- `rm`/`cp` are interactive aliases: use `rm -f`; copy with python. `dart format` reflows whole files: format only files you touched.
- Read test verdicts with: `... 2>&1 | tr '\r' '\n' | grep -E 'All tests passed|Some tests failed'`.
- `engine_core`, `engine_cli`, `engine_schema` use `dart test`; the rest use `flutter test` (with `flutter_test`).

### Gates (a step names which it needs)
- **G1 core**: `cd packages/engine_core && dart analyze --fatal-infos && dart test`
- **G2 all packages**: G1 plus the same analyze/test in `engine_cli`, `engine_schema` (`dart`) and `engine_flutter`, `engine_platformer`, `engine_strategy`, `engine_idle` (`flutter analyze --fatal-infos --no-pub && flutter test --no-pub`). Required for any change to an exported core API.
- **G3 perf**: run `packages/engine_core/benchmark/{world_step,entity_churn,collision_system,world_view,particle_system}_benchmark.dart` and `packages/engine_platformer/benchmark/*` before and after; allowed regression 10% (owner may change). Required for anything in `World`, `ComponentStore`, archetypes, event bus, systems loop, or any new per-entity wrapper.
- **G4 core purity**: `grep -rE "import 'package:flutter|import 'dart:ui" packages/engine_core/lib` must print nothing (a plain `grep -i flutter` also matches doc comments, so it is not usable); `grep -rE "Random\(|DateTime\.now" packages/engine_core/lib` must only hit `deterministic_random.dart` (plus any file allow-listed by Phase 7).
- **G5 docs/ops**: when ops/docs changed, regenerate with `cd packages/engine_core && dart run tool/gen_bundled_docs.dart` and `cd packages/engine_api && dart run tool/gen_api_docs.dart > ../../docs/reference/operations.md`; `git diff` shows only intended regeneration (a drift test fails if stale).
- **G6 end-to-end**: for CLI or cross-package dependency changes, run `game_agent create` against the pushed ref (or scratch copy offline) and confirm the generated project analyzes and tests.

### Baseline (measured 2026-11-02, working tree with 18 uncommitted/untracked files from other work)
| Package | analyze --fatal-infos | tests |
|---|---|---|
| engine_core | clean | 1302 pass |
| engine_schema | clean | 18 pass |
| engine_flutter | clean | 551 pass |
| engine_platformer | clean | 348 pass |
| engine_strategy | clean | 46 pass |
| engine_idle | clean | 196 pass |
| engine_cli | clean | 131 pass (was 129 + 1 fail; see 0.2) |
| engine_api | clean | 61 pass |
| engine_studio | clean | 449 pass (445 + 4 new GitPanel tests) |
(engine_core is 1322 with the 20 golden tests from 0.6.) The numbers above were re-measured on a clean HEAD (the two uncommitted alias files in `world.dart`/`component_registry.dart` were stashed and restored).

Benchmark baseline (single run, 2026-11-02, this machine; lower is better; expect noise, so for G3 compare the median of 3 runs before vs after, same session, same load):
| Benchmark | small | medium | large |
|---|---|---|---|
| world_step (movement only, n=100/1000/5000) | 7.3 us | 67.7 us | 358.5 us |
| entity_churn (spawn+destroy, n=100/1000/5000) | 1654 us | 16738 us | 84422 us |
| collision_system (packed, n=100/1000/5000) | 177 us | 1798 us | 509476 us (superlinear; very noisy) |
| world_view nearestWithPosition (50/200/1000) | 58.5 us | 662 us | 13849 us |
| particle_system (emitters=10/100/500) | 63.4 us | 621 us | 3327 us |
| platformer full_pipeline (enemies=10/100/500) | 50.0 us | 672 us | 3240 us |
| platformer tile_collision (n=50/500/2000) | 238 us | 2311 us | 9215 us |
Run commands: core `cd packages/engine_core && dart run benchmark/<name>_benchmark.dart`; platformer needs the Flutter engine (`dart run` fails on dart:ui): `cd packages/engine_platformer && flutter test --no-pub benchmark/<name>_benchmark.dart`. macOS has no `timeout` command. The 10% threshold (D6) is tighter than run-to-run noise on the large sizes, so judge regressions on small/medium sizes and repeat before concluding.

### Decisions (D1-D6 CONFIRMED by owner 2026-11-02: defaults in bold accepted)
- **D1 canonical collection accessor.** `World.components` is already the `ComponentRegistry` field, so the name is taken. **Keep `world.componentsOf<T>()` as the one public collection accessor; remove `component<T>()` and `getComponentStore<T>()` aliases; deprecate `storeOf<T>()`.** Value access is `getComponent/setComponent/hasComponent/removeComponent`; skip the `get/set/has/del` short aliases (API-explosion rule).
- **D2 Entity handle.** **Extension type `Entity(EntityId)` (zero-cost), keep `typedef EntityId = int`.**
- **D3 core facade name.** `Game` exists in `engine_flutter`. **Name the core one `GameBuilder` (setup) and leave Flutter's `Game` untouched.**
- **D4 auto-registration.** **Explicit registration stays for JSON loading; `GameBuilder` registers defaults for you; no hidden global registration.**
- **D5 scenes.** **Stay in `engine_flutter`; core gets no `Scene` type.**
- **D6 benchmark threshold.** **10% on the benchmarks named in G3.**

### Phased plan
Each step lists: change -> required tests -> gate. "Docs" always means doc comments; extra docs are named.

#### Phase 0: Stabilize (no new API)
- [x] 0.1 Tree clean. The 16 validated files were committed; the two alias-WIP files (`world.dart`, `component_registry.dart`) were discarded by owner decision since Phase 1.1 re-implements the needed part (`getComponent/setComponent/hasComponent/removeComponent`, `componentsOf<T>()`) with docs and tests. The registry-level `get/set/has/remove` aliases are intentionally not carried over.
- [x] 0.2 Diagnosed `first_level_tutorial_test`: real bug, pre-existing on clean HEAD. `game_agent studio` writes its undo journal to `.studio/undo/` next to the level it edits (`assets/levels/.studio/undo/*.json`), and `validate` then scanned those journal files as levels ("missing required key entities"). Fixed in `studio_command.dart` `_levelFiles` (skips `.studio`), regression test `engine_cli/test/level_files_journal_test.dart`. `engine_cli` now green (131).
- [x] 0.3 Benchmark baseline recorded (table above).
- [x] 0.4 Confirmed regeneration commands (no step 0.4 guess needed): operations reference = `cd packages/engine_api && dart run tool/gen_api_docs.dart > ../../docs/reference/operations.md` (from `docs/contributing-docs.md`; a drift test fails when stale); bundled docs = `cd packages/engine_core && dart run tool/gen_bundled_docs.dart`. Use these in G5.
- [x] 0.6 Golden-behavior tests added: `packages/engine_core/test/golden_behavior_test.dart` (20 tests) pins event ordering, destroy-during-iteration and id reuse exactly as they behave today, so Phases 2/3 can show precisely what they change. Findings it locks (correcting earlier notes): events from systems are delivered after all systems ran; a handler-emitted event is delivered in a later round of the same flush; handlers match on exact runtime type; the 20-round cascade cap **defers** the remainder to the next flush (nothing is dropped); forward destroy-while-iterating skips every other entity; a stale id aliases the entity that reused the id and reports alive; ids are reused last-freed-first. When a later phase intentionally changes one of these, update that test in the same commit and say why in the message.
- [x] 0.5 Owner answers D1-D6: defaults accepted 2026-11-02.

#### Phase 1: Component access cleanup (applies D1)
- [x] 1.1 `World` gains `componentsOf<T>()`, `getComponent`, `setComponent`, `hasComponent`, `removeComponent` (documented, tested in `world_component_access_test.dart`). **Plan change: `storeOf` is NOT deprecated here.** `dart analyze --fatal-infos` treats `deprecated_member_use` as a failure and there are ~250 `storeOf` call sites, so deprecating now would turn every gate red. Deprecation moves to 7.final, after the migration has driven the call sites to zero. The in-flight extra aliases (`component`, `getComponentStore`, registry-level `get/set/has/remove`) were never committed and are not added.
- [x] 1.2 Dead-entity semantics: `setComponent` on a dead or never-spawned id throws `StateError` naming the entity (ids are recycled, so a stale write would leak onto the next entity that reuses the id); `getComponent`/`hasComponent`/`removeComponent` on a dead id are null/false/no-op. Raw `storeOf<T>().set` is unchanged and still allows writes to dead ids (pinned by the golden id-reuse tests); migrating call sites in Phase 7 therefore *tightens* behavior, so each migrated directory must be gate-checked.
- [x] 1.3 Destroy safety tests: all stores, archetype index and serialization forget a destroyed entity. **Finding for Phase 3:** the archetype index is only updated by registry-level writes (`applyJson`/`removeEntity`), not by `store.set`/`setComponent`, so `world.archetypes` is *not* a reliable source for `query<A,B>` today. 3.1 must either make `setComponent`/`removeComponent` notify the archetype manager (cost: it recomputes the entity's type set over every registration, which needs a G3 benchmark) or build queries on the stores directly (iterate the smallest store, check `has` on the others). Pinned by a test so this cannot be forgotten.

#### Phase 2: Safe mutation foundations (needed before fluent APIs)
- [x] 2.1 Done in 0.6 (`golden_behavior_test.dart`, "destroy during iteration" group).
- [ ] 2.2 `EventBus.on` returns a subscription handle; add `off`/`once`. Handlers still keyed by runtimeType; document. Tests: unsubscribe stops delivery, once fires once, unsubscribe during flush is safe. Gate: G2, G3.
- [ ] 2.3 Entity generations: stale `Entity`/id detection (`world.isAlive(entity)`), without changing the `int` id JSON format. Tests: reuse of a freed id is distinguishable. Gate: G2, G3 (`entity_churn`).
- [ ] 2.4 Deferred ops (`WorldCommands`, name must not collide with editor `command/`): `spawn/destroy/set/remove` queued, applied after the system or at step end. Tests: destroy-while-iterating no longer skips. Gate: G2, G3.
- [ ] 2.5 Debug-mode warning (assert) when a store is mutated while iterated, pointing at `WorldCommands`. Tests with `expect(() => ..., throwsA(...))` under asserts. Gate: G1.
- [ ] 2.6 `onCollision*` helpers return handles and auto-unsubscribe when the entity dies. Gate: G2.

#### Phase 3: Queries and entity ergonomics
- [ ] 3.1 `world.query<A>()`, `query2<A,B>()`, `query3<A,B,C>()` over `ArchetypeManager`, yielding tuples/records of (id, components); read-only iteration, safe with Phase 2 deferral. Tests: correctness vs naive store join, results after add/remove/destroy. Gate: G2, G3 (new benchmark `query_benchmark.dart` required).
- [ ] 3.2 `Entity` extension type (D2): `get/set/has/remove/destroy/isAlive`. Pure sugar, no new storage. Tests: handle ops hit the world. Gate: G2.
- [ ] 3.3 `world.spawnWith([...])` and `world.entity()` fluent builder (`.at()`, `.with()`, `.named()`); builder must go through registered components so `toJson` still works. Tests: spawned entity round-trips through `World.toJson/applyPatch`. Gate: G2.
- [ ] 3.4 Spawn shortcuts `spawnAt(x,y)`; genre ones (`spawnSprite`, `spawnBody`) go in `engine_flutter`/`engine_platformer`, not core. Gate: G2.
- [ ] 3.5 Tag/marker components: one `Tag`/marker helper with registered JSON. Gate: G1.

#### Phase 4: Systems
- [ ] 4.1 `System` gains optional `enabled` and a `world.setSystemEnabled(name, bool)`; profiler names unchanged. Existing systems unaffected. Gate: G2, G3.
- [ ] 4.2 `SystemGroup` (one `addSystem`); preserves unique child names. Gate: G2.
- [ ] 4.3 Phases (`prePhysics/physics/postPhysics/late`) as an optional `System.phase` with default; ordering = (phase, insertion). Regression tests for the known order hazards (JumpSystem vs tile grounding, Movement before Collision). Gate: G2, G3.
- [ ] 4.4 Order validation: `world.validateSystemOrder()` returns problems (missing required predecessor), used by `game_agent lint`/doctor. Gate: G2, G5 if an op is added.
- [ ] 4.5 Function-based systems (`system('name', (world, dt) {...})`). Gate: G1.

#### Phase 5: Determinism and time (applies findings under "Determinism")
- [ ] 5.1 Attach `DeterministicRandom` to `World` (`world.random`), make its stream position snapshot-able (store seed + draw count or state), include it in `WorldSnapshot` only if that does not break the net/rollback tests (`rollback_session`). Tests: snapshot/restore reproduces the same next draws. Gate: G2.
- [ ] 5.2 Fixed-timestep accumulator helper (`FixedStepper`) in core, used by `GameBuilder`. Tests: variable frame dt gives identical tick sequence. Gate: G1.
- [ ] 5.3 Timer component + `world.after/every` with cancel handle, registered/serializable. Tests: fires once at the right tick, survives snapshot/restore. Gate: G2.
- [ ] 5.4 G4 purity grep wired into a test (`test/core_purity_test.dart`) so it cannot rot.

#### Phase 6: Presets and the core builder
- [ ] 6.1 `SystemPresets.core(world)` in core (Movement, Collision, Tween, Particle, AI, etc., in verified order). Per-genre presets live in `engine_platformer`/`engine_strategy`/`engine_idle` wrapping the existing `install*Systems`. Tests assert `systemOrder` exactly. Gate: G2.
- [ ] 6.2 `GameBuilder.create(...)` (D3): registers components (D4), installs preset, returns `world` + `update(dt)` + `spawn`. Tests: <15-line bouncing-sprite hello world in `engine_core/test`, and an equivalent in `engine_flutter`. Gate: G2, G4.
- [ ] 6.3 `world.update(dt)` alias, `start/pause/stop`, `save()/load()` thin wrappers over `step`, `toJson`, `applyPatch`. Gate: G2.

#### Phase 7: Migration (mechanical, per directory, one commit each)
Order: `ecs/` -> `physics/` -> `ui/` -> `content/` -> `ai/` -> `turn/` -> `idle/` -> `net/` -> `engine_flutter` -> `engine_platformer` -> `engine_strategy` -> `engine_idle` -> `engine_studio`.
- [ ] 7.n Replace `world.storeOf<T>()` with `componentsOf<T>()` / `getComponent` etc. in that directory only; no behavior change. Gate: G2 + G3 for hot paths (`physics/`, `turn/order_system.dart`). Confirm with `grep -rc storeOf <dir>` going to 0 for the directory.
- [ ] 7.final Make `storeOf` removal a separate, owner-approved step after one release (downstream projects pin `ref: main`).

#### Phase 8: Agent/API parity and documentation
- [ ] 8.1 For each new public convenience that has a data-level meaning (spawn with components, timers, destroy-deferred), decide: operation + `game_agent` command, or documented exemption in `docs/reference/operations.md` notes. Gate: G5.
- [ ] 8.2 `applyPatch` strict/dry-run mode returning structured problems (dead ids, missing `entities`, unknown component), exposed via the existing `world.patch` op. Gate: G2, G5.
- [ ] 8.3 `world.debug()` text summary. Gate: G1.
- [ ] 8.4 Docs: update `docs/reference/cheatsheet.md`, `docs/getting-started.md`, tutorials to the new API; add tested `doc_examples_*_test.dart` for each new snippet; regenerate bundled docs. Gate: G2, G5.

#### Phase 9: Testing harness and tooling
- [ ] 9.1 `engine_core_testing.dart` entry point: `GameTester` (`tick`, `advance`, expectations), golden `WorldSnapshot` helper. Gate: G2.
- [ ] 9.2 `game_agent doctor` (registration gaps, `validateSystemOrder`, level problems, dependency-ref mismatch) with the 1:1 operation rule. Gate: G2, G5, G6.
- [ ] 9.3 Update `create` templates to the new minimal API; verify with G6.

#### Phase 10: Remaining backlog (each independent; pick one at a time, same step contract)
`BT.*` factory DSL, steering combinators, `Input` facade, `Camera.follow/shake` audit, parent/child hierarchy, particle pooling (benchmark-led), save versioning/migrations, audio sugar, prefab-registry audit, Tiled mapping polish, turn-based `TurnGame`, debug overlay additions. Each gets its own mini-spec appended here before work starts (files, tests, gate).

### Definition of done for the whole effort
G2 green on a clean tree; G3 within threshold; G4 clean; G5 regenerated; G6 passing; no `storeOf` outside the deprecated shim; the hello-world test exists; every new public member documented.

## Backlog reference (unphased idea list; the phases above draw from this)

## Current state (verified against code, 2026-11-02)
Read before picking items; several "new" ideas below already exist in part. Each section also carries a `> Status:` note.
- **Exists already**: `DeterministicRandom`, `ReplayRecorder`, `WorldSnapshot` (rollback/net), `Tween` + `TweenSystem`, `BTCooldown/BTWait/BTTimer/BTRandomSelector/...` nodes, archetype iteration (`ArchetypeManager`), `SpatialHash`, `raycast.dart`, `CommandHistory` (editor undo), `Scene` + `scene_transition` + menu scenes (`engine_flutter`), `AudioManager`, `debug_overlay`, `save_game`, `Camera`, `World.toJson/applyPatch/componentCounts/systemOrder/profiler`, per-component `ComponentSchema`, `world.query/patch/snapshot/step` operations, `game_agent create --template`, `game_agent lint`, `doc_examples_*_test.dart` compiled-doc tests.
- **Does not exist**: a `Game` facade in `engine_core`, `world.after/every`, `EventBus.once/off`, command buffer, entity generations, parent/child, system phases/groups/enable flags, `SystemPresets`, fluent entity builder, `query2/3`, `BT.*` factory DSL, `game_agent doctor`, a headless test harness (`engine_flutter/lib/src/testing/` is empty).
- **In flight (uncommitted)**: `world.dart` now has `component<T>()`, `getComponentStore<T>()`, `storeOf<T>()`, `componentsOf<T>()` all returning the store, plus `getComponent/setComponent/hasComponent/removeComponent`. See the naming warning under Component-Centric API.
- **Scale of migration**: `storeOf` is used in roughly 30 files in `engine_core/lib` alone (heaviest: `turn/order_system.dart`, `idle/definition.dart`, `content/cinematic.dart`, `turn/gathering.dart`).

## Philosophy
- [ ] **Components only**: Everything attachable to entities is a component. Never speak of "stores" in public API. Think in `getComponent/setComponent/hasComponent/removeComponent`.
- [ ] **Convention over configuration**: Sensible defaults everywhere. A minimal game should work with < 20 lines of code.
- [ ] **Explicit over magic**: When magic is used, it's discoverable and documented. No hidden global state.
- [ ] **Pure core**: `engine_core` stays Flutter-free. All platform integration goes in `engine_flutter`.
- [ ] **Data-driven friendly**: JSON/level data should be easy to load and spawn without manual wiring for every type.

## Quick Start DX
> Status: `Game` already exists as an **abstract class in `engine_flutter`** (`logic/game.dart`), so a core `Game` needs a different name (e.g. `GameBuilder`/`GameSetup`) or an explicit relationship (core `Game` that the Flutter one extends), or two public `Game` types will clash for consumers importing both. Genre install helpers exist per package (`installPlatformerSystems`, `installStrategySystems`); `SystemPresets` should wrap those, not duplicate them, and respect the DAG (core cannot call platformer/strategy installers; presets for those live in their packages).
- [ ] **Game facade**: Add `Game` class in `engine_core` with `Game.create(width, height, {systems})` that auto-registers components, adds sensible system presets, and exposes `world`, `update(dt)`, `spawn()`, etc.
- [ ] **Auto-register on demand**: Allow components to self-register or auto-register when first used. Eliminate the need to manually call `registerCoreComponents` in most cases.
- [ ] **System presets**: Add `SystemPresets.core(world)`, `SystemPresets.platformer(world)`, `SystemPresets.topdown(world)`, `SystemPresets.turnBased(world)`, `SystemPresets.idle(world)`. Each adds systems in correct dependency order with one call.
- [ ] **Entity factory**: Add `world.entity()` returning a fluent builder, or `world.spawnWith([Component1(...), Component2(...)])`. Support `..add()`, `..withX()`, chaining.
- [ ] **Spawn shortcuts**: `world.spawnAt(x,y)` creates entity with `Position(x,y)`. `world.spawnSprite(...)`, `world.spawnBody(...)` for common patterns.
- [ ] **Minimal hello-world**: Test that a bouncing sprite can be made in < 15 lines with new API.

## Component-Centric API (No "Store" Leaks)
> Status: `World.getComponent/setComponent/hasComponent/removeComponent` already exist (uncommitted). **Naming collision**: `world.component<T>()` currently returns the whole store, but the item below wants `component<T>(id)` returning a nullable value. Pick one before more code depends on it. Also the uncommitted diff adds four aliases for the same store accessor (`component`, `getComponentStore`, `storeOf`, `componentsOf`), which is the API-explosion problem this file warns about; keep one canonical name and deprecate the rest. Archetype iteration exists (`Archetype.dense<T>()`, `ArchetypeEntity.get<T>()`) but is not wrapped by `query/query2/query3`. `Entity` is currently only `typedef EntityId = int`; `EntityManager` recycles ids with no generation counter.
- [ ] **Decide canonical store accessor name** and remove the three redundant aliases from `World` (and from `ComponentRegistry` if mirrored) before the deprecation pass.
- [ ] **Resolve `component<T>()` vs `component<T>(id)`** (return type conflict) in one decision, recorded here.
- [ ] **Rename conceptually**: In all public APIs, comments, docs, errors - use "component" not "store". `ComponentStore` can remain as internal impl but never exposed as "Store API".
- [ ] **World component access**: Add `world.getComponent<T>(id)`, `world.setComponent<T>(id, T value)`, `world.hasComponent<T>(id)`, `world.removeComponent<T>(id)`. Add `world.component<T>(id)` as shorthand returning nullable.
- [ ] **Entity handle**: Create lightweight `Entity` or `EntityRef` with `get<T>()`, `set<T>(v)`, `has<T>()`, `remove<T>()`, `destroy()`. Pass these around instead of raw ints where ergonomic.
- [ ] **Component container access**: `world.components<T>()` returns the component collection for iteration/querying. `world.allComponents<T>()` for dense iteration.
- [ ] **Query helpers**: Add `world.query<T>()`, `world.query2<A,B>()`, `world.query3<A,B,C>()` returning iterators/tuples. Hide archetype complexity.
- [ ] **Migrate incrementally**: Replace `storeOf<T>()` with component-centric APIs on every file touched. Don't add new `storeOf` usages.
- [ ] **Deprecation path**: Mark `storeOf` deprecated with clear migration message pointing to component APIs.

## Smarter World API
> Status: `EventBus` has only `on<T>`, `emit`, `flush`, `clearHandlers`. There is **no unsubscribe, no `once`**, so `world.on` auto-unsubscribe needs `on` to return a handle first. Handlers are keyed by `event.runtimeType` (a subclass event will not reach a base-type handler); document or fix. Flush caps at 20 cascade rounds and defers the remainder to the next flush (pinned in `golden_behavior_test.dart`); a runaway self-emitting handler therefore never terminates a step's flush cleanly, so dev mode should warn. `World.step` already exists (add `update` as an alias only if you accept another alias). `onCollisionBetween/Involving/WithAny` already exist in `ecs/event_helpers.dart`, so the "collision callbacks" item is mostly done: expose them via the facade and add unsubscribe. `World.dispose()` exists and shuts down the job system only; it does not clear event handlers or systems.
- [ ] **Return a subscription handle from `EventBus.on`** (prerequisite for `once`, `off`, scene-scoped listeners).
- [ ] **Leak guard**: `onCollision*` helpers register forever and are never removed when the entity dies; tie them to entity lifetime.
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
> Status: `System` is just `{ String get name; void update(World, double dt) }`; `World` keeps a flat `_systems` list in insertion order and exposes `systemOrder` (names only). No phases, groups, enable flags or dependency declarations exist. `WorldProfiler` already times each system by `name`, so any group/phase wrapper must keep unique, stable names. `installPlatformerSystems` has an `includeAnimation` flag that CLAUDE.md names as the one accepted flag exception; phases should replace such flags rather than add more. Order bugs are historically real here (`JumpSystem` vs tile grounding), so auto-ordering needs a regression test per declared dependency.
- [ ] **System ordering enforced**: Core dependencies (Movement before Collision) enforced or auto-sorted.
- [ ] **System groups**: `SystemGroup([sys1, sys2])` can be added as one unit.
- [ ] **Phase-based systems**: `updatePhase` (prePhysics, physics, postPhysics, late) for better organization.
- [ ] **Conditional systems**: Enable/disable systems easily without removing them.
- [ ] **System context**: Pass `dt`, `world` cleanly. Consider `System.update(context)`.
- [ ] **ECS queries built-in**: Systems can declare queries (`query of: [Position, Velocity]`) and iterate efficiently.
- [ ] **Less boilerplate**: Function-based systems or mixins to reduce class ceremony.

## AI, Behavior Trees & State Machines
> Status: `ai/behavior_tree.dart` already has node classes `BTSequence/Selector/Parallel/Inverter/Repeater/Succeeder/Failer/Leaf/Wait/Cooldown/RandomSelector/RandomSequence/UntilSuccess/UntilFailure/Timeout/Throttle/Timer` plus `BTNode.fromJson`, and `BehaviorTreeGraph` (graph editor) compiles to it. So `BT.cooldown`, `BT.random`, `BT.wait`, `BT.repeat` are **factories over existing nodes**, not new nodes; keep JSON shape unchanged. `steering.dart`, `flee_behavior.dart`, `state_machine.dart` exist; the "composable Steer" item is about combinators, not new behaviors. `BT.inRange/seeTarget/ifHasTarget` are new and need `WorldView` access (check what `BTContext` exposes before promising them).
- [ ] **Fluent BT DSL**: `BT.sequence([BT.ifHasTarget(...), BT.chase(), BT.wait(0.5)])` much cleaner than deep nesting.
- [ ] **BT node factories**: `BT.leaf('idle')`, `BT.selector([...])`, `BT.repeat(n, child)`, `BT.forever(child)`.
- [ ] **Inline behaviors**: `Behavior((view, self) => MoveAction(...))` for trivial cases without full classes.
- [ ] **BT helpers**: `BT.inRange(radius, child)`, `BT.seeTarget(child)`, `BT.random([children])`, `BT.cooldown(sec, child)`.
- [ ] **AI helpers**: `ai.setBehavior('chase')`, `ai.runTree(root)`, hide memory keys.
- [ ] **Blackboard sugar**: `blackboard.get/set/has/inc` with type safety.
- [ ] **Steering made easy**: `Steer.seek(arrive(wander(...)))` composable.
- [ ] **State machine DSL**: Cleaner JSON or builder API.

## Levels, Prefabs & Assets
> Status: `content/prefab.dart` (+ `command/prefab_commands.dart`, `ops/groups/prefab_ops.dart`), `Level.loadInto`, `LevelDocument`, `level_validator.dart`, `tmx_import/export.dart`, and `AssetHotReload` (`engine_flutter/logic/asset_hot_reload.dart`) already exist. Treat "Prefab registry", "Tiled integration" and "Hot reload friendly" as **audit-and-polish**, not greenfield: check the existing prefab API against the proposed `register/spawn` shape first. The "validation with fixes" item should extend `level_validator.dart` messages (and the `problems_ops` output) rather than add a second validator.
- [ ] **Asset loading**: Integrate with Flutter/assets or simple file loading. `Level.fromAsset('levels/1.json')`.
- [ ] **Prefab registry**: `PrefabRegistry` with `register('enemy', {...})`, `spawn('enemy', pos)`.
- [ ] **Auto-spawn from prefab**: Attach `PrefabRef` component and have system spawn it, or just call directly.
- [ ] **Component defaults on spawn**: Level loader fills missing defaults intelligently.
- [ ] **Validation with fixes**: Errors say "missing Position on entity 'player', add {\"type\":\"position\",\"x\":0,\"y\":0}".
- [ ] **Tiled integration smoother**: Easier mapping from Tiled objects/tiles to components/prefabs.
- [ ] **Hot reload friendly**: Level/prefab changes easy to reload in dev.

## Physics, Collision & Movement
> Status: `physics/raycast.dart` (`RaycastHit`), `spatial_hash.dart`, `pathfinding.dart`, `collision_system.dart` exist, so `world.raycast` and `world.findNear` are **extension-method wrappers** (`on World`, same pattern as `CollisionEventHelpers`), not new engines. Check whether the spatial hash is rebuilt per step or persistent before exposing `findNear` as cheap.
- [ ] **Simple movement**: `Movement.move(entity, dir * speed * dt)` helpers.
- [ ] **Collision callbacks**: Easier to react to collisions without manual event wiring.
- [ ] **Tilemap helpers**: `tilemap.isSolid(x,y)`, `tilemap.getTile(x,y)` with world/tile coords conversion.
- [ ] **Raycast API**: Simpler `world.raycast(from, to)` returning hits.
- [ ] **Spatial queries**: `world.findNear(pos, radius)` returns entities/components easily.

## Turn-Based Simplification
> Status: `installStrategySystems`/`spawnStrategyUnit` (`engine_strategy`), `OrderQueue`, `selection.dart`, `turn_system.dart`, `ai_turn.dart` exist. `TurnGame.setup`, `unit.do(...)` and `game.select(...)` should wrap these (orders already queue via `OrderQueue`). Lives in `engine_strategy`, not core, where it needs Flutter-side wiring.
- [ ] **One-call setup**: `TurnGame.setup(world)` wires everything.
- [ ] **Action API**: `unit.do(MoveTo(x,y))`, `unit.do(Attack(target))` queued automatically.
- [ ] **Turn flow**: `game.nextTurn()`, `game.endPlayerTurn()` with callbacks.
- [ ] **Selection**: `game.select(entity)`, `game.selectAll([ids])`, `game.commandSelected(action)`.
- [ ] **AI turns**: Opt-in, simple to customize.

## Input & UI
> Status: `InputState`, input bindings storage, gamepad manager/remap menus, on-screen controls, `Camera`, `animation_shake_system.dart`, `cinematic_camera_steps.dart` (pan/zoom/shake/follow steps) all exist in `engine_flutter`. "Input manager", "action mapping" and "camera helpers" are therefore mostly **unification and discoverability** work (one `Input.isPressed(...)` facade over existing bindings; `camera.follow/shake` on `Camera` itself, if not already there). `core/content/action_aliases.dart` exists, so check overlap before adding another mapping layer.
- [ ] **Input manager**: `Input.isPressed(Key.up)`, `Input.getAxis()`, unified across platforms.
- [ ] **Action mapping**: Bind keys/buttons to game actions.
- [ ] **UI helpers**: Simpler button/trigger wiring with callbacks.
- [ ] **Camera helpers**: Follow target, bounds, shake.

## Error Messages & Debugging
> Status: `WorldPatchException` already gives indexed messages ("entities[i].id must be an int, got ..."), the model to copy. `World.componentCounts()`, `WorldProfiler` and `engine_flutter` `debug_overlay.dart`/`debug_memory.dart` exist, so `world.debug()` is a thin text summary over `componentCounts` + `systemOrder` + `entities.count`. Note `applyPatch` silently skips dead entity ids (`if (!entities.isAlive(rawId)) continue;`) and returns early when `entities` is missing; the dry-run/strict mode should report these.
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

## Time, Timers & Tweens (suggested)
> Status: `rendering/tween.dart` + `tween_system.dart` already provide a serializable `Tween` component and system, so the tween item is "friendly constructor over the existing component", not a new system. Timers: no `world.after/every` exist; BT has `BTWait/BTCooldown/BTTimer` but only inside trees. A timer component must be registered (JSON-serializable) per CLAUDE.md or it silently won't save/snapshot.
- [ ] **Timers without systems**: `world.after(1.5, () => ...)`, `world.every(0.5, ...)`, cancellable handles. Backed by a component/system so they serialize or at least die with the world.
- [ ] **Tween helper**: `world.tween(entity, (Position p) => p.x, to: 100, duration: 0.3, ease: Ease.outQuad)` for juice (UI, pickups, screen shake) without hand-written systems.
- [ ] **Cooldown component**: One shared `Cooldown` / `Timer` component instead of each feature (attack, jump buffer, invuln) rolling its own float.
- [ ] **Coroutine-style sequences**: `world.sequence([wait(1), () => spawn(...), wait(2)])` for cutscenes/scripted events.

## Determinism, Replay & Randomness (suggested)
> Status: `DeterministicRandom(seed)` (`ecs/deterministic_random.dart`), `ReplayRecorder` (`ecs/replay_recorder.dart`, generic per-frame JSON) and `WorldSnapshot.capture/restore` (`net/world_snapshot.dart`, used by `rollback_session.dart`) **already exist**, plus `World.setTick`. Gaps: the RNG is not attached to `World` (and its internal `Random` state is not serializable, only the seed, so snapshots do not capture mid-stream position); no fixed-timestep accumulator; `rollback_session` is the consumer to align with. Rewrite items as "wire existing pieces onto `World`/`Game`" plus "make RNG state snapshot-able". Also audit for `Random()`/`DateTime.now()` in `engine_core/lib` (a grep found none outside `DeterministicRandom`, but re-run it as a CI check).
- [ ] **Seeded RNG on the world**: `world.random` (seeded, serializable state). Ban bare `Random()` in engine code so runs are reproducible.
- [ ] **Injectable clock**: No `DateTime.now()` in simulation; time only enters through `update(dt)`.
- [ ] **Fixed-timestep option**: `Game.create(fixedStep: 1/60)` with accumulator so physics doesn't depend on frame rate.
- [ ] **Input recording / replay**: Record inputs + seed, replay to reproduce bugs. Great for agents verifying behavior headlessly.
- [ ] **Snapshot / rewind**: `world.snapshot()` / `world.restore(s)` (cheap undo, tests, turn-based "undo move").

## Scenes & Game Flow (suggested)
> Status: `Scene` (`engine_flutter/logic/scene.dart`), `scene_transition.dart`, `snapshot_transition.dart` and menu/settings/save-slot/credits scenes already exist, and TODO.md ("Mobarez sample follow-ups") already plans menus and save slots from them. So scenes are **not** a core concept today. Decide: keep them in `engine_flutter` (they render), or extract a Flutter-free `SceneStack` interface into core. Do not create a second `Scene` type.
- [ ] **Scene stack**: `game.push(PauseScene())`, `game.pop()`, `game.replace(...)` with enter/exit hooks. Menu -> play -> game-over without custom state enums.
- [ ] **Scene = level + systems + UI**: A scene bundles which systems run, so presets and levels compose.
- [ ] **Transitions**: Fade/slide between scenes as a built-in.

## Safe Mutation (suggested)
> Status: `World.destroy` removes components immediately and `EntityManager` recycles ids LIFO (`_free.removeLast()`), so a stale id can silently alias a newly spawned entity; events are the only deferred mechanism (`EventBus.flush` after all systems). **Naming warning**: `lib/src/command/` (`EditCommand`, `CommandHistory`) is the *editor undo* system; a runtime command buffer should be named differently (e.g. `DeferredOps`/`WorldCommands`) to avoid confusion. Dense stores swap-remove (`ComponentStore.remove`), so destroying while iterating `denseAt(i)` skips entities, which is the concrete bug the command buffer fixes; add a regression test showing it.
- [ ] **Command buffer**: `world.commands.spawn/destroy/set` deferred to end of system/step so destroying during iteration never corrupts queries. Make it the default inside systems.
- [ ] **Clear failure on mid-iteration mutation**: In debug, throw with a message pointing to the command buffer rather than silently skipping entities.
- [ ] **Entity ID safety**: Generation-checked handles so a stale `Entity` for a destroyed id is detectably dead, not a different new entity.

## Hierarchy & Transforms (suggested)
> Status: confirmed absent (no parent/child or local/world transform types). `Level.loadInto` already supports entity `"name"` lookup (see `content/level.dart`), so `world.find('player')` should reuse that mechanism. A new `Parent` component must be registered and must handle `World.destroy` cascading, which today removes only the one entity.
- [ ] **Parent/child**: `entity.addChild(other)` with local vs world `Position`, auto-destroy children with parent (weapons, shadows, attached emitters).
- [ ] **Named lookup**: `world.find('player')`, `world.findAll(tag: 'enemy')` for common cases without queries.

## Testing DX (suggested)
> Status: `engine_core/test` already has `doc_examples_*_test.dart` (compiled/exercised doc examples), `builder_test.dart`, determinism and snapshot tests; `engine_flutter/lib/src/testing/` exists but is **empty**, a ready home for the Flutter-side harness. A Flutter-free `GameTester` belongs in `engine_core` (e.g. `engine_core_testing.dart` entry point, like the existing `engine_core_ops/idle/io` split) so it is not pulled into production barrels. Golden snapshots can use `WorldSnapshot` rather than a new format.
- [ ] **Headless test harness**: `GameTester` / `testGame(...)` with `tick(n)`, `advance(seconds)`, `press(action)`, and matchers like `expect(entity, hasComponent<Dead>())`.
- [ ] **Golden world snapshots**: Compare `world.save()` against checked-in JSON after N ticks for regression tests.
- [ ] **Test builders**: `TestWorld.withPlayer()` etc. so tests of new features don't repeat setup.

## Agent-Friendliness (suggested; core design goal of the repo)
> Status: every registered component already carries a `ComponentSchema` (`engine_schema`), and `ops/json_schema.dart` + `schema_ops.dart` + `world.query/patch/snapshot/step/build/discard` operations exist, so "self-describing schema" is partly done: check what `schema_ops` already returns before adding `world.describe()`. Dry-run exists at the CLI/op level (`apply: false` / `--dry-run` in `ops_cli.dart`) but **not** on `World.applyPatch`. Each new op must follow the add-operation checklist in `TODO.md` and regenerate `docs/reference/operations.md`.
- [ ] **Self-describing schema**: `world.describe()` / generated JSON Schema for every registered component, so an agent can discover valid shapes instead of guessing.
- [ ] **Dry-run patches**: `world.applyPatch(p, dryRun: true)` returns what would change plus validation errors.
- [ ] **Errors are machine-readable**: Structured error (code, entity, component, suggested fix) in addition to the human message; feeds the "Actionable errors" item.
- [ ] **Operation registry parity**: Every new convenience API (spawnAt, prefab spawn, timers) gets an operation + `game_agent` command per the 1:1 rule in CLAUDE.md, or an explicit documented exemption.
- [ ] **Keep JSON contract**: Fluent builders, entity handles and shortcuts must be sugar over plain JSON-serializable components, never a parallel non-serializable path.

## Tooling & Onboarding (suggested)
> Status: `game_agent create --template` already exists (templates incl. `strategy_game`, `idle_game`; list the rest from `docs/reference/cli.md`), as does `game_agent lint` and `upgrade`. Missing: `doctor`. `docs/` already has `tutorials/`, `examples/`, `reference/cheatsheet.md`, `faq.md`, so the "cookbook" belongs in `docs/examples` or `docs/tutorials` rather than a new `docs/cookbook/`. Doc examples are already tested via `doc_examples_*_test.dart`; extend that pattern rather than adding a doc-extraction tool. Bundled docs are generated into `ops/bundled_docs.g.dart`, so doc edits require regenerating it.
- [ ] **Templates in the CLI**: `game_agent create --template platformer|topdown|turnbased|idle` generating a runnable < 20-line `main`.
- [ ] **`game_agent doctor`**: Checks registration gaps, system-order problems, bad level data, dependency-ref mismatch (see CLAUDE.md known limitation).
- [ ] **Compiled doc examples**: Dartdoc code samples extracted and compiled in CI so the "Documentation with examples" item cannot rot.
- [ ] **Cookbook**: `docs/cookbook/` with short recipes (health bar, pickup, door+key, enemy patrol, dialogue) each backed by a test.
- [ ] **Migration codemod/guide**: Script or doc listing `storeOf` -> component API replacements so downstream projects can move fast.

## Content Polish (suggested)
> Status: `AudioManager`, `AnimationSfxSystem`/`DialogueSfxSystem`, `ParticleEmitter`/`ParticleSystem`/`particle_forces`, `save_game.dart` + `save_codec.dart` and `debug_overlay.dart` exist. Remaining value is facade sugar (`game.sfx('jump')`) and **save versioning/migrations** (check `save_codec.dart` for an existing version field before adding one). Particle pooling: measure first with the existing benchmarks.
- [ ] **Audio sugar**: `game.sfx('jump')`, `game.music('theme')` with name registry and graceful no-op when headless.
- [ ] **Particles preset**: `world.emit(Particles.burst(...))` using pooling.
- [ ] **Save versioning**: Version field plus per-component migration functions so old saves load after component shape changes.
- [ ] **Debug overlay**: Toggleable FPS, entity count, collider outlines, system timings in `engine_flutter`.

## Risks & Guardrails (suggested)
- [ ] **Benchmark gate**: Re-run `packages/engine_core/benchmark/` and `packages/engine_platformer/benchmark/` for any query/world/system change; fluent wrappers must not allocate in hot loops.
- [ ] **Avoid API explosion**: `get`/`getComponent`/`component`/`storeOf` all coexisting is itself a DX bug. Pick the canonical name (suggest `get/set/has/remove`), keep others as documented deprecated aliases with a removal version.
- [ ] **DAG check**: Anything touching `Game`, scenes or input must keep `engine_core` Flutter-free; Flutter-only parts (Input, audio) go behind interfaces in core.
- [ ] **Definition of done per item**: Doc comment, test that fails without it, TODO.md/operations.md updated, `storeOf` usages in touched files migrated.

## Open Questions (suggested)
- [ ] Should `Entity` be a handle object or an extension type over `int` (zero-cost)?
- [ ] Do auto-registered components still work with JSON load order guarantees, or must registration stay explicit for loaded levels?
- [ ] Is `Game` a thin facade over `World` or the new primary entry point (affects what docs lead with)?
- [ ] What is the deprecation window for `storeOf` given downstream generated projects pin `ref: main`?

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
