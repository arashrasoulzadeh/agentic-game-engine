# SIMPLER

Goal: Refactor the engine to be smarter and easier for game developers to write games with less boilerplate, fewer footguns, and clearer APIs.

Focus on DX over coverage of every internal type. Every change must keep `dart analyze --fatal-infos` clean and all tests passing.

**Phases 0-9 are done and removed from this file** (history: `git log`, `CHANGELOG.md`, `docs/concepts/authoring.md`). What shipped: `getComponent/setComponent/hasComponent/removeComponent` + `componentsOf<T>()`, `query/query2/query3`, `Entity`/`EntityRef`, `spawnWith`/fluent builder/`spawnAt`, `EntityTags`, `EventBus` subscriptions, `world.commands`, entity generations, system phases/groups/enable flags/`after:`/`validateSystemOrder`, `FunctionSystem`, `world.random`/`World(seed:)`, `FixedStepper`, `world.after/every`, `CountdownTimer`, `SystemPresets.core`, `GameBuilder`/`GameLoop`, `world.save()/load()`, `checkPatch`/strict `applyPatch`, `world.debug()`, `engine_core_testing` (`GameTester`, `expectGolden`), `project.doctor`, the authoring guide, the `storeOf` -> `componentsOf` migration and migrated templates.

## HOW TO USE THIS FILE (read first)
Everything below is **open work**. Do steps strictly in order within a phase; a step may start only when every earlier step is committed and its gate is green. Items marked **DECISION** need the owner's answer first; do not guess.

### Agent protocol
1. One step = one commit. Never batch steps. Commit only when its gate is green (CLAUDE.md allows commit+push per completed TODO item).
2. Before editing: re-read the files you will touch (they change). Check `git status`; do not mix your work with unrelated uncommitted changes.
3. Every step ships: code, doc comments on every new public member (the *why*), and a test that **fails without the change**. Bug fix = regression test.
4. Backward compatible first: add new API, mark old `@Deprecated('use X')`, never delete in the same step as the replacement.
5. If a gate fails, fix forward in the same step or `git restore` the step's files. Never weaken or delete an existing test to get green; never commit red.
6. Never un-gitignore `test_game/`; never add a sample app. Keep `engine_core` Flutter-free; respect the DAG `engine_core -> engine_flutter -> engine_platformer` (genre-general data in core, genre logic in the genre package).
7. New component => register in the right `register*Components` with `toJson/fromJson` + schema. New operation => follow the add-operation checklist in `TODO.md` (agent-API section), add the 1:1 `game_agent` command, regenerate the reference docs (G5).
8. Commit message: explain *why* (what broke / how found / why fix works), end with the attribution line the session was given.
9. Stop and ask the owner when: a DECISION is unresolved, a step needs a backward dependency, a benchmark regresses past the threshold, or a gate is red for a reason outside the step.

### Environment (this machine)
- `export PATH="$PATH:/Users/arashrasoulzadeh/develop/flutter/bin"`; pub.dev is unreachable: use `--no-pub`/`--offline`.
- `rm`/`cp` are interactive aliases: use `rm -f`; copy with python. `dart format` reflows whole files: format only files you touched, never `dart format lib`.
- macOS BSD `sed` has no `\b`; there is no `timeout` command.
- Read test verdicts with: `... 2>&1 | tr '\r' '\n' | grep -E 'All tests passed|Some tests failed'`.
- `engine_core`, `engine_cli`, `engine_schema` use `dart test`; the rest use `flutter test`.
- Known flake: `engine_studio` `rename_test` ("Found 2 widgets with key rename-file-use.dart") fails intermittently on full runs; rerun before concluding anything.

### Gates (a step names which it needs)
- **G1 core**: `cd packages/engine_core && dart analyze --fatal-infos && dart test` (includes the purity test: no Flutter/`dart:ui` import, no `DateTime.now` or unseeded `Random()` in simulation dirs).
- **G2 all packages**: G1 plus analyze/test in `engine_cli`, `engine_schema` (`dart`), `engine_api` and `engine_flutter`, `engine_platformer`, `engine_strategy`, `engine_idle`, `engine_studio` (`flutter analyze --fatal-infos --no-pub && flutter test --no-pub`). Required for any change to an exported core API.
- **G3 perf**: run `packages/engine_core/benchmark/{world_step,entity_churn,collision_system,world_view,particle_system,query}_benchmark.dart` and `packages/engine_platformer/benchmark/*` before and after; allowed regression 10%. Required for anything in `World`, `ComponentStore`, archetypes, event bus, systems loop, or any new per-entity wrapper.
- **G5 docs/ops**: when ops/docs/components changed, regenerate: `cd packages/engine_core && dart run tool/gen_bundled_docs.dart`; `cd packages/engine_api && dart run tool/gen_api_docs.dart > ../../docs/reference/operations.md` and `... --transports > ../../docs/reference/transports.md`; `cd packages/engine_schema && dart run tool/gen_component_docs.dart > ../../docs/reference/components.md`. Regenerate bundled docs **last** (it embeds the others) and commit all together; drift tests fail otherwise.
- **G6 end-to-end**: for CLI, template or cross-package dependency changes, run `game_agent create` against the pushed ref (or a scratch copy offline with local path overrides) and confirm the generated project analyzes and tests.

### Current baseline (2026-11-02, clean tree)
Tests: engine_core 1531, engine_cli 132, engine_schema 18, engine_api 61, engine_flutter 552, engine_platformer 352, engine_strategy 47, engine_idle 196, engine_studio 449; analyze `--fatal-infos` clean everywhere.

Benchmarks (median of 3; lower is better; judge regressions on small/medium, the large sizes are noisy):
| Benchmark | small | medium | large |
|---|---|---|---|
| world_step (movement only, n=100/1000/5000) | 7.3 us | 67.7 us | 358.5 us |
| entity_churn (spawn+destroy, n=100/1000/5000) | 1654 us | 16738 us | 84422 us |
| collision_system (packed, n=100/1000/5000) | 177 us | 1798 us | 509476 us |
| world_view nearestWithPosition (50/200/1000) | 58.5 us | 662 us | 13849 us |
| particle_system (emitters=10/100/500) | 63.4 us | 621 us | 3327 us |
| platformer full_pipeline (enemies=10/100/500) | 50.0 us | 672 us | 3240 us |
| platformer tile_collision (n=50/500/2000) | 238 us | 2311 us | 9215 us |
Run: core `cd packages/engine_core && dart run benchmark/<name>_benchmark.dart`; platformer `cd packages/engine_platformer && flutter test --no-pub benchmark/<name>_benchmark.dart`.
Latest: world_step 7.5/68.7 us and collision 180/1813 us (at baseline); **entity_churn about +4% / +5% over baseline** (generation counter on destroy). If it passes 10%, optimize `EntityManager.destroy` before adding anything to that path.

### Decisions (confirmed by owner 2026-11-02)
- D1 `componentsOf<T>()` is the one collection accessor; no `get/set/has/del` short aliases.
- D2 `Entity` extension type is the identity; `EntityRef` carries the ergonomics.
- D3 core facade is `GameBuilder`/`GameLoop`; engine_flutter's `Game` is untouched.
- D4 registration stays explicit for JSON loading; `GameBuilder` registers defaults; no hidden global registration.
- D5 scenes stay in `engine_flutter`; core gets no `Scene` type.
- D6 10% benchmark threshold.

## Open follow-ups from Phases 0-9
- [ ] **7.final** Remove `World.storeOf` (deprecated, no callers except two shim tests). Owner-approved separate step, after one release, because downstream projects pin `ref: main`. Also drop the two shim tests and the deprecation entry in `CHANGELOG.md`. This is the answer to "what is the deprecation window".
- [ ] **DECISION: seed `ParticleSystem` by default.** It defaults to an unseeded `Random()` (allowlisted in `core_purity_test.dart`), so a world with particles is not reproducible unless the caller passes `random:`. Seeding makes particle visuals identical between runs. `SystemPresets.core` already seeds it from `world.seed`.
- [ ] **Idle template widget test fails** (`timewarp-hour` key not found); also failed before this work. Logged in `TODO.md` ("Template health").
- [ ] **Unverified in this environment**: `mkdocs build --strict` (not installable offline; CI `docs` job is the first real check) and `game_agent create` against the pushed ref (G6).
- [ ] **Flaky `engine_studio` `rename_test`**: cause not found.
- [ ] Optional: tutorials 01/03/04 and getting-started still use `componentsOf<T>().set/get` (correct, just older style); hot call sites could move to `getComponent`/`setComponent` where it reads better (note `setComponent` rejects dead entities, a behavior change, so gate each directory).
- [ ] Optional cleanup: move `registerCoreComponents` out of `engine_core.dart` into its own file so `game_builder.dart` does not import the barrel.

## Phase 10: Remaining backlog (each independent; pick one at a time, same step contract)
Each item gets its own mini-spec appended here before work starts (files, tests, gate). Status notes record what already exists so nothing is rebuilt.

### Entity and component ergonomics
- [ ] **Component defaults**: `static const defaults` or builder constructors (`Collider()` with a sensible radius).
- [ ] **Component pooling** for high-churn components (particles); measure first with `particle_system_benchmark`.
- [ ] **Rename conceptually**: remove remaining "store" wording from public docs and error messages (`ComponentStore` may stay as the internal type).

### Systems
- [ ] **System context**: `System.update(context)`. **Blocked by design**: 65 classes `implements System`, so any new member breaks them; needs a migration plan or a wrapper type.
- [ ] **Systems declare their queries** (`query of: [Position, Velocity]`); `query/query2/query3` exist, this is only the declaration sugar.

### AI, behavior trees and state machines
`ai/behavior_tree.dart` already has the node classes and `BTNode.fromJson`; the factories below are sugar over them, JSON shape unchanged. `BT.inRange/seeTarget/ifHasTarget` need `WorldView` access (check what `BTContext` exposes first).
- [ ] **Tree conditions** `BT.inRange`, `BT.seeTarget`, `BT.ifHasTarget`: need `WorldView` queries from `BTContext` (the `BT` factories, `registerFn` and blackboard `has/inc/remove` shipped). Express them as registered behaviors first and see if a factory earns its place.
- [ ] **AI helpers**: `ai.setBehavior`, `ai.runTree`.
- [ ] **Steering combinators**: composable `Steer.seek(arrive(wander(...)))` over existing `steering.dart`.
- [ ] **State machine DSL**: cleaner JSON or builder over `state_machine.dart`.

### Levels, prefabs and assets
Audit-and-polish, not greenfield: `content/prefab.dart`, `Level.loadInto`, `level_validator.dart`, `tmx_import/export.dart`, `AssetHotReload` exist.
- [ ] **Asset loading**: `Level.fromAsset('levels/1.json')`.
- [x] Prefab audit: `Prefab` (data, `prefab.*` operations) existed but had no runtime spawn. `PrefabRegistry.register/registerJson/spawn(world, name, x, y)` shipped; it validates every component up front. **Finding:** `Level.loadInto` (via `applyToEntity`) silently skips unknown component names, so a typo in a level drops the component without a word. See the validation item below.
- [ ] **Auto-spawn from prefab** (`PrefabRef` component).
- [ ] **Component defaults on level load**.
- [ ] **Validation with fixes** (including: warn or fail on unknown component names in `Level.loadInto`; today it silently skips them, by design for forward-compatible patches, so it needs an opt-in strict mode): messages like "missing Position on entity 'player', add {...}"; extend `level_validator.dart`, do not add a second validator.
- [ ] **Tiled mapping polish** and **hot-reload friendliness**.

### Physics, collision and movement
- [x] (`world.move`, `moveToward`, `aimVelocity` shipped.) (`world.raycast`, `world.findNear` and `TileMap` world-coordinate helpers shipped; `findNear` is an O(n) scan, per-frame work should use `SpatialHash`.)

### Turn-based (lives in `engine_strategy`)
- [x] `TurnGame` shipped (`setup`, `spawnUnit`, `start`, `moveTo/attack/defend`, `select/selectAll/commandSelected`, `endTurn`, `activeTeam/round/winner`, `onTurnStarted/onTurnEnded`), a thin wrapper over the existing functions. Not done: a `unit.do(...)` per-entity handle (use `TurnGame.moveTo(unit, ...)`), and the AI is still configured through `aiTeams`.

### Input and UI (`engine_flutter`)
Mostly unification: `InputState`, bindings, gamepad, `Camera`, `animation_shake_system.dart` and cinematic camera steps exist; `core/content/action_aliases.dart` may overlap.
- [ ] **Action mapping and UI wiring.** Camera audited: `followSmooth` shipped and `shake(frequency:)` now oscillates when set (null keeps the original random jitter). (`Input` facade shipped in `input_facade.dart`: `justPressed/justReleased/isDown/axis` over `InputState`; keyboard, touch and gamepad already all write the same named actions.)

### Errors and debugging
`WorldPatchException` is the model for message quality.
- [ ] **Actionable errors**: every "component not found" says how to fix it.
- [ ] **Type-aware errors**: expected vs got.
- [ ] **Dev-mode warnings** beyond system order (missing registration) and helpful debug-only asserts.
- [ ] **Machine-readable errors**: code, entity, component, suggested fix, in addition to the human message.

### API surface cleanup
- [ ] Minimal barrel exports (advanced/internal to subpaths), consistent naming, remove redundancy, extension methods over bloating classes, dartdoc examples on public API.

### Time and tweens
- [ ] **Input recording and replay**: `ReplayRecorder` exists; wire inputs + `world.random` seed so a bug can be reproduced headlessly.

### Scenes and game flow (stay in `engine_flutter`, D5)
- [ ] **Scene = level + systems + UI bundle** (idea only; a `Scene` already bundles populate + assets + camera). Overlay stack, `onEnter/onExit` and full-scene `pushScene/popScene` (suspended world kept alive) shipped; transitions already exist.

### Hierarchy
- [ ] **Named lookup**: `world.find('player')`. Names live only in level JSON (`LevelHandle.named`), not on the world; decide whether to add a registered `Name` component (then `find` is a store scan) or keep names a level concern. `world.withTag(...)` already covers the by-label case. (`Parent`, `addChild`, `childrenOf`, `worldPositionOf` and cascading destroy shipped.)

### Testing
- [ ] **`GameTester.press(action)`** and component matchers (`hasComponent<Dead>()`); **test builders** (`TestWorld.withPlayer()`). The `engine_flutter/lib/src/testing/` directory is empty and is the home for a Flutter-side harness.

### Agent-friendliness
- [ ] **Self-describing schema**: check what `schema_ops` returns before adding `world.describe()`.
- [ ] Keep the JSON contract: fluent builders, handles and shortcuts stay sugar over plain JSON-serializable components; any new convenience API gets an operation + `game_agent` command or a documented exemption (see the table in `docs/concepts/authoring.md`).

### Tooling and onboarding
- [x] `topdown_game` template shipped (core + engine_flutter only, verified offline in a scratch project: analyze clean, widget test passes). `platformer` = `default_game`, `turnbased` = `strategy_game`, `idle` = `idle_game` already existed, so no alias names were added. Still unverified: `game_agent create` against the pushed ref (G6).
- [ ] **Cookbook**: dialogue recipe still missing (health bar, pickup, door+key, patrol, waves exist in `docs/examples`, the last four tested in `doc_examples_pickups_test.dart`).
- [ ] **Migration guide** for downstream projects (`storeOf` -> component API) before 7.final.

### Content polish
- [ ] (`GameAudio` shipped: `sfx/music` by name, `silent()` for headless, unknown names throw even then.) **particles preset** with pooling, (`SaveMigrations` shipped: chained version steps plus rename/add helpers, plugs into `SaveGame.load(migrate:)` via `forVersion`) debug overlay audited: FPS, graphs, entity counts, collider outlines (`GameConfig.showColliderDebug`) and system timings already existed; `DebugOverlay(panels:)` now toggles sections and adds a `World.debug()` panel.

## Standing guardrails
- Components only in public API wording; convention over configuration (a minimal game in < 20 lines); explicit over magic; `engine_core` stays Flutter-free; data-driven friendly.
- Fluent wrappers must not allocate in hot loops: run G3 for anything on a hot path.
- No API explosion: one canonical name per concept, others deprecated with a removal plan.
- Anything touching input, audio or scenes keeps `engine_core` Flutter-free; Flutter-only parts go behind interfaces in core.
- Definition of done per item: doc comment, test that fails without it, `TODO.md` and reference docs updated, `storeOf` not used in touched files.
- Definition of done for the whole effort: G2 green on a clean tree, G3 within threshold, G5 regenerated, G6 passing, no `storeOf` outside the deprecated shim (then none at all after 7.final).
