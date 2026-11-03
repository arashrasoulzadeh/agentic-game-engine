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
- [ ] **7.final** (migration guide shipped: `docs/migrating-from-storeof.md`; still waiting for a tagged release, since `v0.1.0` is only local) Remove `World.storeOf` (deprecated, no callers except two shim tests). Owner-approved separate step, after one release, because downstream projects pin `ref: main`. Also drop the two shim tests and the deprecation entry in `CHANGELOG.md`. This is the answer to "what is the deprecation window".
- [x] **`ParticleSystem` is seeded by default** (`Random(0)`), so a world with particles is reproducible; the `core_purity_test.dart` allowlist is now empty. Pass a differently seeded `random:` for varied visuals.
- [x] **Idle template widget test fixed.** The generated app was fine; the test used the default 800x600 view, so lazy lists never built the time warp and the save button was off-screen. The test now sets a tall view. Verified in an offline scratch project (analyze clean, test passes).
- [ ] **Unverified in this environment**: `mkdocs build --strict` (not installable offline; CI `docs` job is the first real check) and `game_agent create` against the pushed ref (G6).
- [x] **`engine_studio` `rename_test` flake**: passes alone (6/6), so the cause is load: it drives a real analysis server with fixed retry budgets that ran out when the full suite loaded the machine. Budgets raised (20 to 60 and 10 to 30 attempts); no slower when the server is quick.
- [ ] Optional: tutorials 01/03/04 and getting-started still use `componentsOf<T>().set/get` (correct, just older style); hot call sites could move to `getComponent`/`setComponent` where it reads better (note `setComponent` rejects dead entities, a behavior change, so gate each directory).
- [x] `registerCoreComponents` moved to `lib/src/ecs/register_core_components.dart` (still exported from the barrel); `game_builder.dart` no longer imports the barrel.

## Phase 10: Remaining backlog (each independent; pick one at a time, same step contract)
Each item gets its own mini-spec appended here before work starts (files, tests, gate). Status notes record what already exists so nothing is rebuilt.

### Entity and component ergonomics
- [x] Component defaults: `Position()` and `Velocity()` default to zero (optional positional, source compatible). Deliberately not done: a default `Collider` radius (no value is right for every game; the radius is a size decision) and lenient JSON (`{"x": 1}` still fails, which strict level loading relies on).
- [x] **Component pooling: measured, not worth it.** `particle_system_benchmark` steady state is 67 us (10 emitters), 655 us (100), 3360 us (500), about 1.1 us per live particle per step for spawn, move and age together. `entity_churn` shows a full spawn+destroy costs about 0.16 us, so allocation is not the bottleneck; reusing the per-tick `expired` list changed nothing. Revisit only if a profile shows GC pauses in a real game.
- [x] **Rename conceptually**: public docs and messages already say `componentsOf`/"component"; remaining "store" is the `ComponentStore` type name (kept as the internal type, documented in `docs/concepts/ecs.md`) and local variable names. Nothing user-facing left to rename.

### Systems
- [x] **System context**: declined. 65 classes `implements System`, so a new member breaks them all, and `FunctionSystem`/`addSystemFn` plus `WorldView` already give systems a narrow context. Revisit only if a wrapper type is needed by a concrete feature.
- [x] **Systems declare their queries**: declined. `query of: [Position, Velocity]` cannot be typed in Dart (a list of `Type`s loses the element types), so a declaration would add ceremony without safety; `query<A>/query2<A,B>/query3<A,B,C>` already are the declaration and give typed results.

### AI, behavior trees and state machines
`ai/behavior_tree.dart` already has the node classes and `BTNode.fromJson`; the factories below are sugar over them, JSON shape unchanged. `BT.inRange/seeTarget/ifHasTarget` need `WorldView` access (check what `BTContext` exposes first).
- [x] **Tree conditions**, done as registered behaviors (the plan's first step; no new node type needed): `registry.registerCondition(id, test)`, `registerInRange(id, target: 'player', range: 80)` (uses `world.find`), `registerHas<T>(id)`; a condition is a leaf that succeeds or fails, so it composes with `BT.sequence`/`BT.selector`.
- [x] **AI helpers**: `world.setBehavior(entity, id, behaviors:, keepMemory:)` (unknown id fails immediately when a registry is given) and `world.runTree(entity, tree, behaviors:)` (registers the tree as `tree@<entity>` and points `AIState` at it).
- [x] **Steering combinators**: `Steer.seek/flee/arrive/wander` rules over `SteerContext`, composed with `Steer.blend` (weighted, speed-capped), `Steer.firstMoving`, `Steer.onlyWhen(Steer.within(r), rule)`.
- [x] **State machine DSL**: `StateMachineBuilder` (`state`, `transition`, `start`, `build`); `build` rejects undeclared states, duplicate states and a state with both a tree and a behavior, instead of leaving the machine silently idle.

### Levels, prefabs and assets
Audit-and-polish, not greenfield: `content/prefab.dart`, `Level.loadInto`, `level_validator.dart`, `tmx_import/export.dart`, `AssetHotReload` exist.
- [x] **Asset loading**: `LevelAsset.read/load` in `engine_flutter` (`await LevelAsset.load(world, 'assets/levels/1.json', strict: true)`). It lives there, not as `Level.fromAsset`, because `engine_core` cannot touch the Flutter asset bundle.
- [x] Prefab audit: `Prefab` (data, `prefab.*` operations) existed but had no runtime spawn. `PrefabRegistry.register/registerJson/spawn(world, name, x, y)` shipped; it validates every component up front. **Finding:** `Level.loadInto` (via `applyToEntity`) silently skips unknown component names, so a typo in a level drops the component without a word. See the validation item below.
- [x] **Auto-spawn from prefab**: `PrefabRef` component (`prefabRef: {name}`) plus `PrefabRegistry.expandRefs(world, only:)`; `Level.loadInto(prefabs: registry)` expands the placeholders it just loaded at their `Position`, and a named placeholder's name moves to the prefab's first entity. Without a registry placeholders are left alone.
- [x] **Component defaults on level load**: opt-in `Level.loadInto(defaults: true)` fills schema-declared defaults (`{"position": {"x": 5}}` gets `y: 0`); authored values win; fields with no declared default stay required; works with `strict`.
- [x] **Validation with fixes**: strict load (`Level.loadInto(strict: true)`), `LevelValidator` (used by `project.doctor`, `level.validate`, studio) and `checkComponent` all say `did you mean "position"?` for a typo'd component name; a missing required field says `y is missing (add "y": 0)`; a mistyped enum value suggests the closest option. `project.doctor` already uses the schema validator, which is stricter than strict load, so no second validator was added.
- [x] **Tiled polish**: `tileMapFromTmx(xml, layer:)` and `level.import_tmx --layer` choose among several tile layers (an ambiguous map now lists the names); uncompressed base64 layer data imports (flip bits stripped); compressed data names the Tiled setting to change. **Hot reload**: `LevelHandle.load(strict:, prefabs:, defaults:)` carries its options to `reload`, and with `strict` a typo'd edit is rejected before the running level is torn down (without it the typo silently drops the component). Still not supported: several tilesets, external `.tsx`, zlib/gzip.

### Physics, collision and movement
- [x] (`world.move`, `moveToward`, `aimVelocity` shipped.) (`world.raycast`, `world.findNear` and `TileMap` world-coordinate helpers shipped; `findNear` is an O(n) scan, per-frame work should use `SpatialHash`.)

### Turn-based (lives in `engine_strategy`)
- [x] `TurnGame` shipped (`setup`, `spawnUnit`, `start`, `moveTo/attack/defend`, `select/selectAll/commandSelected`, `endTurn`, `activeTeam/round/winner`, `onTurnStarted/onTurnEnded`), a thin wrapper over the existing functions. Not done: a `unit.do(...)` per-entity handle (use `TurnGame.moveTo(unit, ...)`), and the AI is still configured through `aiTeams`.

### Input and UI (`engine_flutter`)
Mostly unification: `InputState`, bindings, gamepad, `Camera`, `animation_shake_system.dart` and cinematic camera steps exist; `core/content/action_aliases.dart` may overlap.
- [x] **Action mapping and UI wiring.** Audited: keyboard, touch and gamepad already write the same named actions, with persisted bindings and a remap menu. Added what was missing: `InputController.defaultBindings(wasd:)`, `bind`, `bindAll`, `unbindAction` (releases a held action) and `keysFor`. Camera: `followSmooth` and `shake(frequency:)` shipped; `Input` facade shipped.

### Errors and debugging
Audited by probing ~20 common mistakes. Good already: unregistered component, dead-entity writes, unknown prefab, bad timers, bad patches, missing `after:` systems. Fixed: component JSON with a missing or mistyped field now says which data arrived and which fields are expected (was a raw "type 'Null' is not a subtype of type 'num'").
- [x] **Debug warnings shipped** (`world.warnings`, `DevWarnings`: collected only in debug builds, shown in `world.debug()`): duplicate system names, component re-registration, and opt-in `warnOnUnhandledEvents`. **Not shipped: warning on `destroy` of a dead entity.** It sits on the hot path and measured +8-9% on `entity_churn` (even as a cold helper method, even returning a bool from `EntityManager.destroy`), which with the earlier drift is past the 10% limit. Owner decision: accept the cost, or find a cheaper hook (e.g. only in `WorldCommands.destroy`).
- [x] **Machine-readable errors**: `EngineError` (`code`, `message`, `toJson()`) is implemented by `WorldPatchException` (`patch_invalid`), `ComponentApplyException` (`component_invalid`, with `entity` and `component`) and `LevelLoadException` (`level_invalid`); strict failures carry located `problems` (`path`, `message`, including any did-you-mean). `world.patch` returns that JSON in the error's `details`. Fix text lives in the message and hint; no separate field was added.

### API surface cleanup
- [x] API surface: non-breaking only. Added `package:engine_core/engine_core_essentials.dart` (the daily-use set, tested by importing only it); the topic barrels (`_idle`, `_io`, `_ops`, `_testing`, `_web`) already existed. Not done on purpose: moving existing exports to subpaths, which would break downstream projects pinned to `ref: main`; revisit with the 7.final release.

### Time and tweens
- [x] **Input recording and replay**: `SessionRecorder(world, captureInput:)` records the seed plus one input snapshot per step; `SessionReplayer.run(freshWorld, saved, applyInput:)` replays it and refuses a world built with a different seed. A test shows the replayed final state equals the recorded one byte for byte, and fails if the inputs differ.

### Scenes and game flow (stay in `engine_flutter`, D5)
- [x] **Scene bundle**: `LevelScene(asset:, setup:, follow:, atlases:, strict:, prefabs:, defaults:)` is a level file plus a setup callback instead of a class per room; the camera follows a named entity via `world.find`. Overlay stack, `onEnter/onExit` and `pushScene/popScene` shipped earlier.

### Hierarchy
- [x] **Named lookup**: decided to add a registered `Name` component (not keep names a level concern). `world.find('player')` (lowest id wins on duplicates), `nameOf`, `setName`; `Level.loadInto` gives every entity with a `name` key this component (skipped when `name` is not registered). `find` is a scan: look up once and keep the id. `world.withTag(...)` still covers many-entities labels.

### Testing
- [x] **Testing helpers**: `GameTester.spawnActor` (named player with Position/Velocity/Collider), `has`, `expectHas<T>`, `expectMissing<T>`, `expectAlive`, `expectDestroyed` (plain throwing helpers, not matchers: `engine_core` deliberately has no test-framework dependency). Input lives in Flutter, so `press` is `InputDriver(state, tick:)` in `engine_flutter/lib/src/testing/` (`press/release/tap/setAxis/releaseAll`), kept free of the dart:io testing library so web builds stay clean.

### Agent-friendliness
- [x] **Self-describing schema**: `schema.components/component/template/validate_component` already described component types; added `world.describe()` and the `world.describe` operation for the live world (counts, each component in use with its schema fields, systems with enabled flags, queued commands, order problems, warnings).
- [x] JSON contract kept: every new convenience API is sugar over plain components or level options; `docs/concepts/authoring.md` has the exemption table, extended with the new APIs (`world.describe` got an operation).

### Tooling and onboarding
- [x] `topdown_game` template shipped (core + engine_flutter only, verified offline in a scratch project: analyze clean, widget test passes). `platformer` = `default_game`, `turnbased` = `strategy_game`, `idle` = `idle_game` already existed, so no alias names were added. Still unverified: `game_agent create` against the pushed ref (G6).
- [x] **Cookbook**: dialogue recipe added (`docs/examples/talk-to-npc.md`, executed by `doc_examples_talk_to_npc_test.dart`): proximity starts the conversation, a choice event changes the game. Health bar, pickup, door+key, patrol and waves existed already.
- [x] **Migration guide** for `storeOf` shipped: `docs/migrating-from-storeof.md`.

### Content polish
- [x] (`GameAudio` shipped: `sfx/music` by name, `silent()` for headless, unknown names throw even then.) **particles presets** shipped as `ParticlePresets.explosion/sparks/smoke/dust` (pooling was measured and ruled out), (`SaveMigrations` shipped: chained version steps plus rename/add helpers, plugs into `SaveGame.load(migrate:)` via `forVersion`) debug overlay audited: FPS, graphs, entity counts, collider outlines (`GameConfig.showColliderDebug`) and system timings already existed; `DebugOverlay(panels:)` now toggles sections and adds a `World.debug()` panel.

## Standing guardrails
- Components only in public API wording; convention over configuration (a minimal game in < 20 lines); explicit over magic; `engine_core` stays Flutter-free; data-driven friendly.
- Fluent wrappers must not allocate in hot loops: run G3 for anything on a hot path.
- No API explosion: one canonical name per concept, others deprecated with a removal plan.
- Anything touching input, audio or scenes keeps `engine_core` Flutter-free; Flutter-only parts go behind interfaces in core.
- Definition of done per item: doc comment, test that fails without it, `TODO.md` and reference docs updated, `storeOf` not used in touched files.
- Definition of done for the whole effort: G2 green on a clean tree, G3 within threshold, G5 regenerated, G6 passing, no `storeOf` outside the deprecated shim (then none at all after 7.final).
