# Studio — PRD, Technical Design, and Phased TODO

Scope: a cross-platform **desktop** authoring studio for games built on this engine. It
covers the level editor, property inspector, visual scripting, asset
pipeline, play-test, and project management. It sits **on top of** the
engine; the engine remains the runtime and stays usable without the
studio.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done.

---

## Part 1 — Product Requirements (PRD)

### 1.1 Problem

Games built on `engine_core`/`engine_flutter`/`engine_platformer` are
authored today by hand-writing JSON (`Level`, `TileMap`, `World` patches)
and Dart (`Scene.populate`, behaviors). That works for an AI agent and
for a developer who knows the format, but it is slow for level design,
hard to review visually, and gives no feedback until the game is run.

### 1.2 Goals

1. A designer can build a playable level (tiles, entities, triggers,
   dialogue hooks) without writing Dart.
2. Every edit is reversible and every saved file is the same JSON the
   runtime loads — no separate "editor format".
3. Logic that today needs code (dialogue flow, cutscenes, AI, quest
   state) can be authored as a graph, and the graph runs on the engine's
   existing systems.
4. Play-test is one click: the level in the editor launches in the
   engine and returns to the editor on exit.
5. AI agents keep first-class access: every studio action has an
   equivalent JSON/CLI operation, so an agent can do what a human does.

### 1.3 Non-goals

- No 3D. The engine is 2D-only by project decision.
- No replacing Flutter as the shell. The studio is a Flutter app.
- No new game engine dependency (no Flame, Unity, Godot).
- No real-time multi-user collaboration in v1.
- No custom scripting language in v1. Logic is graphs or Dart.
- No marketplace/asset store in v1.

### 1.4 Users

| User | Needs |
|---|---|
| Level designer | Paint tiles, place entities, set triggers, undo, play-test |
| Gameplay programmer | Define component schemas, custom nodes, write Dart systems |
| Narrative/designer | Build dialogue and cutscene graphs without code |
| AI agent (Claude, etc.) | Read/write the same JSON through CLI and the agent API |

### 1.5 Core requirements

**Platform requirement (decided by the project owner):** the studio is a
desktop application, cross-platform across **macOS, Windows, and Linux**.
All three are required targets from phase 3 onward, each built and tested in
CI. Web is optional and view-only; it is not a substitute for a desktop build.

**Must have (v1):**
- Open/create a project folder created by `game_agent create`.
- Level editor: tile paint/erase/fill, entity placement, select/move/delete,
  layers, grid snap.
- Property inspector for every registered component, driven by schema.
- Undo/redo for every edit.
- Save to level JSON; load round-trips unchanged (byte-stable for
  unchanged data).
- Play-test a level in the engine and return.
- Validation panel (missing atlas, unknown component, unreachable exit).

**Should have (v2):**
- Visual graph editor for dialogue, cutscenes, and quests, executing on
  the existing `DialogueRunner`/`CinematicSystem`.
- Asset browser with atlas preview and sprite picking.
- Prefab/brush library.
- Tiled (`.tmx`) import/export in both directions.

**Could have (later):**
- Behavior-tree and FSM editing in the same studio (migrate
  `bt_editor_web` in).
- Live reload of assets and levels into a running game.
- Collaboration via shared project folder + git-aware merges.
- Profiler view (frame time, entity counts) fed from the engine.

### 1.6 Success metrics

- A new level with 1 tilemap, 10 entities, and 1 trigger is built and
  play-tested in under 10 minutes by a new user.
- 100% of studio-saved levels load in the engine without a converter.
- Every studio action has a CLI/JSON equivalent (checked by a test list).
- Undo/redo covers 100% of mutating editor commands (checked by a test
  that enumerates command types).

### 1.7 Constraints

- Dependency DAG stays one-way: `engine_core` → `engine_flutter` →
  `engine_platformer` → `studio`. Nothing in the engine may import the
  studio.
- Studio UI logic lives in the studio package; reusable data logic
  (schema, command model, graph model) lives in `engine_core` so the CLI
  and agents can use it without Flutter.
- Follows the repo's conventions (CLAUDE.md): doc comments on every
  public symbol, a test for every behavior, commit per completed item.

---

## Part 2 — Technical Design

### 2.1 Package layout (proposed)

| Package | New content | Depends on |
|---|---|---|
| `engine_core` | `schema/` (component field metadata), `command/` (undo model), `graph/` (node graph data + validator), `project/` (project manifest) | — |
| `engine_flutter` | `editor_runtime/` (render a level without running systems), play-test launcher hooks | `engine_core` |
| `engine_platformer` | Platformer component schemas, platformer graph nodes | `engine_core`, `engine_flutter` |
| `engine_cli` | `studio validate`, `studio export`, `studio import-tmx` | `engine_core` |
| `engine_studio` (new, Flutter app, separately installable) | Editor UI, inspector, graph canvas, asset browser | all of the above |

`bt_editor_web` is an existing standalone app; it moves into `engine_studio` in
phase 4 and is then deleted.

### 2.2 Data model (what the studio reads and writes)

All studio-authored data is plain JSON already consumed by the engine.
No new file formats are introduced in v1.

| File | Content | Existing? |
|---|---|---|
| `project.json` | Project name, engine version, asset roots, default scene list | New (manifest) |
| `levels/*.json` | `Level` (tilemap + entities) | Yes |
| `dialogue/*.json` | `DialogueGraph` | Yes (runner exists) |
| `cinematics/*.json` | `Cinematic` steps | Yes |
| `schemas/components.json` | Field metadata per component (generated) | New |
| `graphs/*.json` | Visual-script graphs (dialogue, cutscene, quest) | New |
| `assets/` | PNG, atlases, fonts, audio | Yes |

Rule: a file the studio saves must load with the engine's existing
loader with no conversion step. A new file type is only added when no
existing one can hold the data.

### 2.3 Component schema (the key enabling piece)

The inspector and the CLI both need to know each component's fields,
types, ranges, and defaults. Today each component hand-writes
`toJson`/`fromJson`, so the field list is not queryable.

Proposal: a **schema descriptor** per component, registered next to the
existing `register*Components` call:

```
ComponentSchema(
  name: 'Health',
  fields: [
    FieldSchema('current', FieldType.int, min: 0, defaultValue: 100),
    FieldSchema('max', FieldType.int, min: 1, defaultValue: 100),
  ],
)
```

- Schemas are data, not reflection. Each component declares its own
  schema, so the "no generic reflective JSON helper" rule in CLAUDE.md
  still holds — the schema is an explicit, reviewable list.
- A test asserts that every registered component has a schema and that
  each schema's fields match the component's `toJson` keys. This keeps
  the two from drifting.
- The schema drives: the inspector UI, `studio validate`, the agent API
  (so an agent can see what it can set), and default values for new
  entities.

**Open decision D1:** hand-written schemas (explicit, more code) vs.
code generation from annotations (less code, adds a build step). Default
recommendation: hand-written in phase 1, revisit generation once there
are more than ~40 components.

### 2.4 Command model (undo/redo)

Every mutation in the studio is a `Command` object:

```
abstract class EditCommand {
  String get label;
  void apply(LevelDocument doc);
  void revert(LevelDocument doc);
}
```

- `LevelDocument` is the editable in-memory level (plain data, no
  `World`). Commands mutate it; the view re-renders from it.
- Undo stack holds applied commands. Merging: consecutive paint strokes
  merge into one command.
- Save = serialize `LevelDocument` to the level JSON. Load = build
  `LevelDocument` from JSON. A round-trip test asserts unchanged data is
  byte-stable.

**Open decision D2:** whether the command model lives in `engine_core`
(usable by CLI/agents for scripted edits) or in `engine_studio` only. Default
recommendation: `engine_core`, so an agent edits levels through the same
commands a human uses.

### 2.5 Editor rendering without running the simulation

The engine assumes one live `World` with systems ticking. The editor
needs a static view:

- Build a `World` from `LevelDocument`, register components, render via
  `EngineView`, but **do not install systems** (no gravity, no AI).
- Hit-testing (select entity under cursor) uses `Position` + `Sprite`
  bounds, computed in a pure function so it is unit-testable without
  Flutter.
- Grid, layer, and selection overlays are drawn by the studio, not the
  engine.

### 2.6 Visual scripting model

A graph is data:

- `Graph` = nodes + edges + variables. Each node has a `kind` string, typed
  input/output ports, and a JSON `params` map.
- Node kinds come from a registry (`NodeKind` with port schema and an
  execution function). Built-ins: dialogue say/choice, set/get variable,
  branch, wait, play cutscene, emit event, spawn entity, call behavior.
- **Execution** compiles a graph to the engine's existing primitives:
  dialogue nodes become a `DialogueGraph`, cutscene nodes become
  `Cinematic` steps. The graph does not add a new runtime — it is a
  second authoring format for the runtime that already exists. This is
  the central design decision: no parallel interpreter.
- Validation (`Graph.validate`) checks port types, unreachable nodes,
  missing entry node, and cycles without a wait node.

**Open decision D3:** graphs compile to existing primitives only (limited
expressiveness, no new runtime) vs. a small interpreter that can express
more (more code, more to test). Default: compile-only in v2; add an
interpreter only if a real game needs a construct the compiler can't
express.

### 2.7 Play-test flow

1. Studio saves the level to a temp project snapshot.
2. Launches the game runner (`game_agent` run, or an embedded
   `GameRunner`) pointed at that level as the start scene.
3. On exit (or a hotkey), the studio regains focus and reloads the level
   if the game wrote back a save slot — not the level itself.

**Open decision D4:** embedded play (same process, mounted in a studio
panel) vs. separate process (simpler, isolates crashes). Default:
separate process in v1.

### 2.8 Asset pipeline

- Studio reads the project's `assets/` folder; `pack_assets` builds
  atlases. Studio shows the packed result and sprite names.
- Atlas changes trigger a validation pass (sprite names referenced by
  levels still exist).
- Hot-reload (phase 5) watches the folder and invalidates
  `AtlasRegistry` entries — it reuses the existing registry, no new
  cache.

### 2.9 Validation

One validator in `engine_core`, used by the studio (live), `studio
validate` (CLI), and CI:
- Unknown component type, invalid field value against its schema.
- Missing sprite/atlas referenced by a level.
- Dangling references (trigger targets a missing entity).
- Graph errors (see 2.6).
- Unreachable exit (level flood-fill from spawn, reusing the existing
  tile-map traversal).

### 2.10 Agent and CLI parity

Every studio operation has a headless equivalent:

| Studio action | CLI / API |
|---|---|
| Create project | `game_agent create` (exists) |
| Validate | `game_agent studio validate` |
| Export level | `game_agent studio export` |
| Import TMX | `game_agent studio import-tmx` |
| Edit level | `EditCommand` applied via agent API |
| Build atlases | `game_agent pack-assets` (exists) |

A test enumerates the studio's command list and asserts each has a
headless entry point. This keeps agents from being second-class users.

### 2.11 Testing strategy

- `engine_core` (schema, commands, graph, validator): plain `dart test`,
  100% coverage target, no Flutter.
- `engine_flutter` editor rendering: `flutter test` with
  `testWidgets` for layout and plain `test()` for asset decoding (avoid
  the FakeAsync/Ticker deadlock documented in `packed_atlas_test.dart`).
- `engine_studio` UI: widget tests for inspector and canvas; golden tests for
  the level view.
- End-to-end: a script creates a project, edits a level through commands,
  saves, runs `studio validate`, and loads it in a headless `GameRunner`.
  Run in CI.
- Every command type has an undo/redo test that fails if `revert` does
  not restore the prior document exactly.

### 2.12 Risks

| Risk | Mitigation |
|---|---|
| Schema drift between components and inspector | Test that schema fields match `toJson` keys |
| Undo bugs corrupt levels | Round-trip and revert tests per command; save snapshots |
| Graph format becomes a second runtime | Decision D3: compile to existing primitives |
| Flutter web canvas perf for large levels | Virtualized tile rendering; benchmark at 500×500 |
| Scope creep into a full IDE | Phases gate features; v1 is level editor only |
| `dart format` on this SDK reformats unrelated code | Format only new files; hand-format edits (see CLAUDE.md conventions) |

---

### 2.13 Distribution, install, and update

`engine_studio` is its own Flutter application in its own package, with its
own `pubspec.yaml`. It is installed separately from the engine: a user
installs the studio once and uses it to create and open game projects. It
does not need the engine repo checked out.

**Packaging per platform:** macOS `.dmg`, Windows `.msi`, Linux
`.AppImage`. A web build is optional and view-only, and is never the
primary editing surface.

**What "auto download required packages" means.** A compiled Flutter app
cannot run `pub get` for code it doesn't already contain, so the studio
splits the work into two parts:

- The studio binary ships with the engine packages it needs to render
  levels and run play-test. These are fixed per studio release.
- On first launch and on each start, a **bootstrap window** checks a signed
  release manifest and downloads what is missing or outdated: project
  templates, sample levels, node and brush packs, and the engine version
  a project targets. Each download is shown with name, size, progress, and
  a checksum result.

The bootstrap window also reports **updates**: a list of what changed
(studio version, engine version, packs), what each change affects, and
whether it needs a restart. The user can accept, defer, or skip each item.
Nothing is installed without that confirmation.

**Game projects** still get their engine packages through `pub` (the
self-referencing git dependency convention in CLAUDE.md), so the studio
never has to replace a project's dependencies behind the user's back.

**Trust and integrity:**
- Manifests and packs are signed. The studio refuses unsigned or
  checksum-mismatched downloads and says why in the window.
- The studio never executes downloaded code. Packs are data (JSON, PNG,
  node definitions); any downloaded behavior has to go through the node
  registry, not a plugin loader (see phase 7.5).
- Downloads are cached per version so an offline launch still opens
  existing projects.

**Failure handling:** a failed download leaves the previous version in place,
shows the error in the window, and offers retry. The studio must open
existing projects even if the manifest server is unreachable.

## Part 3 — Phased Implementation

Each phase ends with a shippable state and a green test suite.

### Phase 0 — Foundations (engine-side, no UI)

Goal: the data contracts the studio depends on exist and are tested.

- [x] **0.1** Component schema type (`ComponentSchema`, `FieldSchema`,
  `FieldType`) in `engine_core/lib/src/schema/`.
- [x] **0.2** Schema registration in `registerCoreComponents`,
  `registerFlutterComponents`, `registerPlatformerComponents`.
- [x] **0.3** Test: every registered component has a schema; schema
  fields match `toJson` keys.
- [x] **0.4** Test: every field default is valid for its own field
  (`component_schema_coverage_test.dart`). Not "defaults alone pass `fromJson`":
  required fields have no default, so a component cannot be built from defaults
  alone.
- [x] **0.5** `LevelDocument` (editable plain-data level) with
  `fromJson`/`toJson`.
- [x] **0.6** Round-trip: a legend-authored level (the default template) keeps
  its data, key order, and ASCII rows through a save, and saving twice gives
  identical output (`level_document_roundtrip_test.dart`). Not "byte-identical
  to the original file": the template's hand-written spacing is not what a
  JSON encoder emits. The round-trip avoids `TileMap.fromJson` on purpose,
  since that would rewrite the legend as flat ids.
- [x] **0.7** Decide D1 (schemas hand-written) and record it in
  `docs/adr/0001-hand-written-component-schemas.md`.

### Phase 1 — Command model and validation (engine-side)

Goal: every change is an undoable command; bad data is caught before the
game runs.

- [x] **1.1** `EditCommand` base type with `apply`/`revert` in
  `engine_core/lib/src/command/`.
- [~] **1.2** Commands: `PlaceTile`, `EraseTile`, `FillRegion`,
  `AddEntity`, `RemoveEntity`, `SetComponentField`, `MoveEntity`,
  `SetLayer`.
- [x] **1.3** `CommandHistory` with undo/redo stacks and stroke merging.
- [x] **1.4** Test per command: `apply` then `revert` restores the
  document exactly.
- [x] **1.5** Test: history undo/redo ordering and stroke merge.
- [x] **1.6** Decide D2 (commands in `engine_core`) and record it.
- [x] **1.7** `LevelValidator` in `engine_core/lib/src/validation/`:
  unknown component, field out of range, dangling entity refs.
- [x] **1.8** Reachability check (flood-fill from spawn over the tile
  map) — reuses existing tile traversal.
- [~] **1.9** Tests for each validator rule, including a passing level.
- [x] **1.10** Decide D4 (play-test process model) and record it.

### Phase 2 — CLI and headless tooling

Goal: an agent or CI can do everything a designer can, without a UI.

- [x] **2.1** `engine_cli` command `studio validate <project>` — runs
  `LevelValidator` over all levels, exits non-zero on errors.
- [x] **2.2** `studio export-levels` — writes levels in engine JSON
  (no-op for native files; reserved for Tiled export in phase 5).
- [x] **2.3** `studio import-tmx <file>` — wraps existing
  `tmx_import.dart`, writes `levels/*.json`, runs validator.
- [x] **2.4** `studio project-manifest` — creates/updates `project.json`.
- [ ] **2.5** Test: each CLI command has a golden-output test and an
  exit-code test.
- [ ] **2.6** End-to-end script: create project → apply commands → save
  → validate → load in headless `GameRunner`. Added to CI.
- [ ] **2.8** `game_agent lint --playable` runs its own flood-fill, separate
  from `isTileReachable` (engine_core). Make `lint` call `isTileReachable` so the
  CLI and the validator cannot disagree about reachability.
- [ ] **2.7** Verify end-to-end against the **pushed** repo (CLAUDE.md
  rule): `game_agent create` a project and run `studio validate` on it.

### Phase 3 — Level editor (engine_studio app, v1 MVP)

Goal: a designer builds, saves, and play-tests a level.

- [~] **3.1** (scaffold done for macOS, Windows, Linux; the macOS build is blocked by a broken CocoaPods install, see the note on 3.1) Create `packages/engine_studio` (Flutter app, depends on
  `engine_core`, `engine_flutter`, `engine_platformer`). Add to CI.
- [x] **3.2** Project open screen: a native folder picker (Browse) or a typed path, validated (pubspec.yaml, assets/levels), then opens the first level. Reading `project.json` is deferred to the 2.4 manifest, which the screen does not need yet.
- [x] **3.3** Static level view: draws `LevelDocument` (tiles by collision kind, entity markers and names) without running systems. Deviation: drawn directly, not through `EngineView`, which needs sprite atlases that arrive with the asset browser (5.1).
  with no systems installed (see 2.5).
- [x] **3.4** Pure hit-test function for selection, with unit tests.
- [x] **3.5** Tools: select, move, tile paint, tile erase, fill, entity
  place. Each tool emits commands only.
- [ ] **3.6** Grid snap and layer visibility toggles.
- [~] **3.7** (undo/redo buttons done; keyboard shortcuts not yet) Undo/redo keybindings and toolbar buttons bound to
  `CommandHistory`.
- [ ] **3.8** Property inspector generated from component schemas
  (phase 0.1). Widget per `FieldType`.
- [ ] **3.9** Entity palette: list of component templates with defaults
  from schemas.
- [ ] **3.10** Validation panel: live `LevelValidator` results, click to
  focus the offending entity.
- [ ] **3.11** Save/load level JSON; autosave to a backup file, not the
  level itself.
- [ ] **3.12** Play-test button: saves snapshot, launches game runner
  process on that level, returns on exit (D4 default: separate process).
- [ ] **3.13** Widget tests: inspector per field type; tool emits the
  right command.
- [ ] **3.14** Golden test for the level view on a fixed sample level.
- [ ] **3.15** Manual verification checklist recorded in
  `docs/studio/qa-level-editor.md`, run on macOS, Windows, and Linux.
- [ ] **3.16** Performance check: 500×500 tile level pans and paints at
  60 fps on the reference machine; numbers recorded.

- [ ] **3.17** `engine_studio` package scaffold with its own `pubspec.yaml`
  depending on the engine packages by git ref (same convention as other
  packages). Builds on macOS first.
- [ ] **3.18** Bootstrap window: lists required downloads, shows progress,
  size, and checksum result per item; retry on failure (section 2.13).
- [ ] **3.19** Signed release manifest format (`manifest.json` + signature)
  and a verifier in `engine_core`, with tests for valid, unsigned,
  tampered, and checksum-mismatch manifests.
- [ ] **3.20** Update notices: the bootstrap window lists version changes
  with per-item accept/defer/skip; nothing installs without confirmation.
- [ ] **3.21** Offline mode: previously cached versions open existing
  projects when the manifest server is unreachable; test with a fake
  unreachable server.
- [ ] **3.22** Packaging scripts for `.dmg` first; `.msi` and `.AppImage`
  added in phase 6 once the macOS flow is verified end to end.

**Phase 3 exit criteria:** PRD metrics 1.6 (10-minute build + play-test)
and the undo coverage test are both green.

### Phase 4 — Visual scripting and dialogue/cutscene graphs

Goal: narrative and cutscene logic authored as graphs, running on
existing runtime primitives.

- [ ] **4.1** Decide D3 (compile-only) and record it.
- [ ] **4.2** Graph data model in `engine_core/lib/src/graph/`: `Graph`,
  `GraphNode`, `GraphEdge`, `PortType`, variables.
- [ ] **4.3** `NodeKind` registry with port schemas.
- [ ] **4.4** Built-in node kinds: `Say`, `Choice`, `SetVar`, `GetVar`,
  `Branch`, `Wait`, `PlayCinematic`, `EmitEvent`, `SpawnEntity`.
- [ ] **4.5** `Graph.validate`: port type mismatch, unreachable nodes,
  missing entry, cycles without `Wait`.
- [ ] **4.6** Compiler: dialogue subgraph → `DialogueGraph`; cutscene
  subgraph → `Cinematic` steps. Round-trip tests against the existing
  runners.
- [ ] **4.7** Test: a compiled dialogue graph produces the same runner
  events as a hand-written `DialogueGraph`.
- [ ] **4.8** Migrate `bt_editor_web` node-canvas code into
  `engine_studio/lib/graph/` as the shared canvas widget.
- [ ] **4.9** Graph canvas widget: pan, zoom, connect ports, select.
- [ ] **4.10** Node inspector (params generated from node kind schema).
- [ ] **4.11** Save/load `graphs/*.json`; validation panel shows graph
  errors alongside level errors.
- [ ] **4.12** Widget tests for connect/disconnect and invalid-connection
  rejection.
- [ ] **4.13** Retire `packages/bt_editor_web` once the studio canvas
  covers its features; update docs and TODO.md.

### Phase 5 — Assets, prefabs, interchange

Goal: content pipeline is complete for real projects.

- [ ] **5.1** Asset browser: lists `assets/`, previews atlases, shows
  sprite names from `pack_assets` output.
- [ ] **5.2** Sprite picker used by `Sprite` field in the inspector.
- [ ] **5.3** Validator: referenced sprite/atlas missing → error with
  jump-to-reference.
- [ ] **5.4** Prefabs: save an entity group as `prefabs/*.json`; place as
  one command (`InstantiatePrefab`), undoable as one step.
- [ ] **5.5** Brush library: tile and prefab brushes, reusable across
  levels.
- [ ] **5.6** Tiled export (`studio export-tmx`) and round-trip test
  against `tmx_import.dart`.
- [ ] **5.7** Asset hot-reload: watch `assets/`, invalidate
  `AtlasRegistry` entries, reload open levels (this also closes the
  TODO.md "Asset hot-reload" item).
- [ ] **5.8** Tests for prefab undo as a single step.

### Phase 6 — Behaviors, profiling, polish

Goal: the studio covers AI authoring and gives performance feedback.

- [ ] **6.1** Behavior-tree and FSM editing in the studio, reusing the
  graph canvas from phase 4.
- [ ] **6.2** Profiler panel: frame time, system timings, entity counts,
  fed from an engine-side metrics hook (also closes the TODO.md
  "Performance profiling tools" item in part).
- [ ] **6.3** Debug overlay improvements hooked into the same metrics
  feed (closes "Debug overlay improvements").
- [ ] **6.4** Keyboard shortcut map, customizable, stored as
  `studio_prefs.json` (not in the project).
- [ ] **6.5** Accessibility pass on studio UI: keyboard navigation,
  contrast, screen-reader labels.
- [ ] **6.6** Localization of studio strings via the existing
  `LocalizationManager`.
- [ ] **6.7** Documentation: `docs/studio/` user guide, screenshots,
  and a "build your first level" tutorial, following the examples
  checked against current signatures.

### Phase 7 — Stretch (not scheduled)

- [ ] **7.1** Live reload of levels into a running game over a local
  socket.
- [ ] **7.2** Git-aware diff/merge view for level JSON.
- [ ] **7.3** Collaborative editing via shared project folder with
  lock files.
- [ ] **7.4** Embedded play-test in a studio panel (D4 alternative).
- [ ] **7.5** Plugin API for third-party node kinds and inspector widgets.

---

## Part 4 — Open Decisions

| ID | Question | Default | Decide by |
|---|---|---|---|
| D1 | Component schemas hand-written or generated? | Hand-written | Phase 0 |
| D2 | Command model in `engine_core` or `studio`? | `engine_core` | Phase 1 |
| D3 | Graphs compile to existing primitives only, or own interpreter? | Compile only | Phase 4 |
| D4 | Play-test as separate process or embedded? | Separate process | Phase 1 |
| D5 | Studio self-update: platform updater (Sparkle/WinSparkle) or notify-and-link to installer? | Notify-and-link in v1 | Phase 3 |

## Part 5 — Milestones

| Milestone | Phases | Outcome |
|---|---|---|
| M0 Foundations | 0–1 | Data contracts, undo, validation — no UI |
| M1 Headless | 2 | CLI/CI can validate and import/export levels |
| M2 Level editor MVP | 3 | Build and play-test a level in the studio |
| M3 Narrative graphs | 4 | Dialogue/cutscenes authored visually |
| M4 Content complete | 5 | Assets, prefabs, Tiled interchange, hot-reload |
| M5 Full studio | 6 | Behaviors, profiler, docs, polish |

## Part 6 — Relationship to TODO.md

Items in `TODO.md` that this document absorbs:
- "Level editor integration" → phases 0–3, 5.4–5.5
- "Visual scripting / node editor" → phase 4
- "Asset hot-reload" → phase 5.7
- "Performance profiling tools" → phase 6.2
- "Debug overlay improvements" → phase 6.3

When a phase item lands, check it here and update the matching `TODO.md`
entry in the same commit.
