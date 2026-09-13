# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

Everything completed through the "New engine features"/`lib/src/`
restructure streak has been cleared from this file — see
[CHANGELOG.md](CHANGELOG.md) for what shipped and git history for the
full why behind each change.

## v1.0 release readiness

Not feature work — what an actual 1.0 tag needs beyond "the features
in this file are done." An engine can ship 1.0 with a smaller, stable
feature set; it can't ship without these. Checked directly against the
repo, not from memory.

- [x] `LICENSE` file: MIT, at the repo root plus a copy in each of the
      four packages (`packages/*/LICENSE`) since pub.dev's per-package
      publish validation looks for a `LICENSE` in that package's own
      root, not just the repo root.
- [x] `pubspec.yaml` metadata: added `homepage`/`repository` (both
      pointing at the GitHub repo) to all four packages. No `license:`
      field added — that's not a real pub.dev-recognized pubspec key;
      pub.dev auto-detects license from the `LICENSE` file above.
- [x] API stability commitment: new "API stability" section in the root
      `README.md` — the contract is each package's top-level export
      surface (`<package>.dart`), `src/` internals stay free to move at
      any version; explicitly documents `Text`/`Velocity`/`Action`'s
      Flutter-name-collision `hide`-workaround (19 existing call sites)
      as a deliberate, permanent decision rather than a pre-1.0 wart to
      fix — renaming would be a bigger, lower-value breaking change than
      the `hide` pattern it replaces.
- [x] Root-level getting-started walkthrough: re-checked against the
      actual current `README.md` rather than assumed — its existing
      "Quick start" section already does exactly this (install the CLI,
      `game_agent create`, `cd`, `flutter run`, all in one place), so
      this item was already satisfied when written; no change needed.
- [x] Malformed-input robustness: `Level.validate`/`TileMap.fromJson`
      already threw clear, specific exceptions — the real gap was two
      layers underneath: `ComponentRegistry.applyToEntity` and
      `World.applyPatch` (both entity-patch-JSON entry points, used by
      `Level.loadInto`, `SaveGame.load`, and any agent calling
      `applyPatch` directly) did raw, unguarded type casts, so a
      malformed component value or patch shape threw a bare, contextless
      Dart `TypeError`/`CastError` instead of anything catchable/
      debuggable. New `ComponentApplyException` (component name + entity
      id + underlying cause) and `WorldPatchException` (which part of
      the patch shape was wrong) close that gap, mirroring
      `LevelLoadException`'s existing design. `SaveGame.load` also
      guards its top-level JSON decode (a corrupted/non-object save now
      throws `LevelLoadException` instead of a bare cast failure).
      Verified: new tests in `component_registry_test.dart` (3),
      `world_test.dart` (7), and `save_game_test.dart` (2) covering both
      the error paths and that valid/unknown-component input still
      works exactly as before; full `engine_core`/`engine_flutter`/
      `engine_platformer`/`engine_cli` suites green, all four analyzers
      clean.

## Tooling / release

- [ ] Publish `engine_core`/`engine_flutter`/`engine_cli` to pub.dev —
      removes the git-ref-matching constraint entirely via normal semver
- [ ] Test on a real Android/iOS device — **partial progress**:
      `flutter build apk --release` for `test_game` now succeeds
      (43.1MB, real release build, not just web debug) — confirms
      release-mode compilation/R8 minification doesn't break anything.
      `flutter build ios --release --no-codesign` failed on this
      environment's broken CocoaPods (Ruby/CocoaPods version mismatch)
      — a local sandbox issue, not an engine bug, not attempted to fix
      here since it'd mean touching system Ruby/CocoaPods outside this
      repo's scope. Neither build has actually been *installed and run*
      on a real device or emulator — no Android device/emulator tooling
      available in this environment, only an iOS Simulator control tool
      that's moot while the iOS build itself won't compile here.
      Orientation lock, lifecycle pause/resume, and real-world
      performance remain genuinely unverified outside Flutter web debug.

## Features (engine_flutter)

- [ ] Real masking/clipping: z-index only reorders draw *calls*; it has
      no clip-path or blend-mode primitive, so it can't express "this
      shape cuts a hole in what's behind it" or "this layer only shows
      through a mask shape." Would need its own API (e.g. a `Mask`/
      `ClipShape` component and a `Canvas.clipPath`/`saveLayer`+
      `BlendMode.dstIn` pass in `EngineView`) — worth doing once there's
      a concrete use case (fog-of-war reveal, a vignette, a wipe
      transition).

## New engine features (round 2)

Gaps identified in a follow-up pass once the previous "New engine
features" streak (text rendering, debug viz, raycasting, AI depth,
HUD/UI, folder restructure) landed — grouped by which package each
belongs in.

### Core (`engine_core`)

- [ ] Multi-layer / animated tiles: `TileMap` is single-layer with no
      per-tile animation (torches, water) — most real levels want at
      least a background/foreground layer split.
- [ ] Deterministic RNG + replay/record: no seeded RNG helper and no
      input-replay capture exist yet, both of which matter for
      reproducible testing/debugging of an agent-driven or
      physics-heavy game.
- [x] Save-schema versioning: scoped to `SaveGame` (`engine_flutter`) —
      the actual save/load surface this concerned, not `World.toJson()`/
      `GameState` in isolation, which have no persistence story of
      their own to version (a game persisting `GameState` itself is
      already outside `SaveGame`'s scope). `SaveGame.save` now takes a
      `version` (default `1`) and wraps the World snapshot in a
      `{schemaVersion, world}` envelope instead of storing it bare.
      `SaveGame.load` takes a matching `version` plus an optional
      `migrate` callback (raw saved JSON + its saved version -> current-
      shape JSON); a version mismatch with no `migrate` throws a new
      `SaveVersionException` instead of either silently loading
      wrong-shaped data or surfacing a confusing
      `ComponentApplyException` from deep inside `Level.loadInto`. A
      save written before this existed (no envelope — the decoded map
      itself never has a `"world"` key, since `World.toJson()` never
      produces one) is detected and treated as version `1`, so existing
      saves keep loading unchanged. Verified: 4 new tests in
      `save_game_test.dart` (round-trip at a non-default version,
      mismatch-with-no-migrate throws, mismatch-with-migrate loads the
      migrated data, a legacy no-envelope save is read as version 1)
      plus the full existing suite still green — 11/11 in that file,
      full `engine_flutter` suite passing, analyzer clean (bar the
      one pre-existing unrelated lint in `button_menu_scene_test.dart`).
- [x] Spatial range queries: `WorldView.entitiesWithinRadius(x, y,
      radius, {exclude})` — linear scan, same approach and caveat as
      `nearestWithPosition` (fine at single-query scale; reach for
      `SpatialHash` directly in a System at bigger scale). Scoped to a
      circle, not also a rect variant — every AoE/perception use case
      this engine has actually needed so far is a radius; add rect if a
      real one shows up rather than building it speculatively. Did not
      reuse `spatial_hash.dart`'s internal grid directly since it's
      rebuilt fresh by `CollisionSystem` every tick and discarded, not
      persisted state a `WorldView` query could reach into. Verified: 2
      new tests in `world_view_test.dart` (in-range/on-edge/out-of-range/
      excluded-self, and an empty-result case) — 162 `engine_core` tests
      passing, analyzer clean.
- [x] Multi-component query helper: `WorldView.entitiesWithAll<A, B>()`
      — scans whichever of the two component stores is currently
      smaller and checks the other via a direct `has` lookup, since
      neither component is privileged in a two-component query and the
      smaller-first scan is strictly cheaper. For three or more
      components, chain `.where(hasComponent<C>)` on the result rather
      than growing this into a variadic-arity API nobody's asked for
      yet. Verified: 3 new tests in `world_view_test.dart` (basic
      filtering, correctness regardless of which store happens to be
      smaller, empty result) — 160 `engine_core` tests passing, analyzer
      clean.
- [x] Priority-queue-backed pathfinding open set: `findPath`'s open set
      is now a private binary min-heap (`_MinHeap`, in
      `pathfinding.dart` — small enough that a `package:collection`
      dependency wasn't worth adding for it) instead of a sort-then-
      take-first list: O(log n) insert/extract-min instead of
      O(n log n) every iteration. No decrease-key — a node can be
      pushed more than once if a cheaper route to it is found later;
      the existing `closed`-set check already discards a stale
      duplicate the moment it's popped a second time, so this stays
      correct without the extra bookkeeping a real decrease-key would
      need. Behavior-preserving: every existing `findPath` test passed
      unchanged (the algorithm's actual logic didn't change, only the
      open-set data structure). Verified: 1 new test in
      `pathfinding_test.dart` — a 20×20 maze-like grid (400 cells, a
      wall spanning column 10 with a single gap) forcing a real detour
      through many more add/removeMin cycles than the existing small
      tests exercise, asserting both the exact shortest-path length
      (38, computed independently via Manhattan distance to the
      mandatory gap) and that the path only ever crosses the wall at
      that gap; full `engine_core` suite (161 tests) green, analyzer
      clean. `_MinHeap`/`_Node` are library-private to `pathfinding.dart`
      (each `.dart` file is its own library in Dart, so even a test
      file importing it directly by relative path couldn't reach
      them), so this is verified through `findPath`'s own observable
      behavior rather than a unit test of the heap in isolation.
- [ ] Content hot-reload: no way to re-load a level/`GameConfig` JSON
      file into a running `World` without a full app restart — this
      engine markets itself as agent-friendly/iteration-friendly, and
      fast content-edit-see-result loops are a big part of that promise
      that isn't delivered yet.

### Rendering (`engine_flutter`)

- [x] Multi-line / wrapped `Text`: new `maxWidth` field (`null` default
      — today's original unbounded single-line behavior). `EngineView`
      passes it straight through to `TextPainter.layout(maxWidth:)`,
      scaled by `Camera.zoom` in world space the same way `fontSize`
      already is (so the wrap point stays visually consistent at any
      zoom level) — Flutter's own `TextPainter` does the actual line-
      breaking; nothing hand-rolled. Rich formatting (mixed styles/
      colors within one string) intentionally left out — no concrete
      use case yet, and `TextSpan` children could be added later
      without touching this field if one shows up. Verified: 2 new
      tests in `text_test.dart` (defaults/round-trip) + 2 new rendering
      tests in `text_rendering_test.dart` (wraps without crashing,
      unbounded text still renders at nonzero zoom); visually confirmed
      in the browser — a long line with `maxWidth: 180` wrapped onto 5
      lines correctly in `test_game` (reverted after, gitignored).
- [x] Tile culling for large maps: `_collectTileMapItems` now converts
      the viewport's on-screen rect to world-space (via
      `Camera.screenToWorld`, already existed for tap handling) then to
      tile-grid indices, with a 1-tile margin (a tile straddling the
      edge still draws) and clamped to the map's actual bounds — turns
      an unconditional O(rows×cols) walk into O(visible tiles),
      regardless of total map size. A degenerate 0×0 map is guarded
      against explicitly (would otherwise `clamp(0, -1)` and throw).
      Scoped to the normal renderer only, not `_drawTileMapDebug`'s
      debug-overlay walk — that's an opt-in dev-only diagnostic, lower
      priority, left as a possible follow-up rather than folded in here.
      Verified: new regression test in `tile_rendering_test.dart` — a
      2000×2000 (4,000,000-tile) `TileMap` renders in well under a
      second (bounded to <3s, generous to avoid flakiness — the point
      is "doesn't scale with total tile count," not a precise number);
      full existing test still passes unchanged. Also verified visually
      in the browser (not just unit tests): `test_game`'s real level
      still renders its floor/platforms/staircase correctly.
- [x] 9-slice sprites: new `NineSliceSprite` component (`engine_flutter`)
      — an atlas region split into a 3×3 grid by
      `insetLeft`/`insetTop`/`insetRight`/`insetBottom`, corners at
      native size, edges/center stretched to fill `width`/`height`.
      Always screen space, same "no concrete world-space use case yet"
      reasoning `HudBar` already documents. Drawn as 9 individual
      `Canvas.drawImageRect` calls rather than
      `Canvas.drawImageNine` — checked, and that method always
      nine-slices the *whole* source image with no sub-rect parameter,
      useless against one packed region within a shared atlas image. A
      destination cell that would come out zero/negative size (e.g.
      `width`/`height` smaller than the insets sum to) is skipped rather
      than handed to `drawImageRect`. Verified: 8 new tests in
      `nine_slice_sprite_test.dart` (round-trip, defaults, renders
      without crashing, the degenerate-small-size skip case, missing-
      atlas/missing-Position graceful skips); full `engine_flutter`
      suite green, analyzer clean. Also verified visually in the
      browser: rendered at the correct position/size in `test_game`
      (reverted after, gitignored) — though with the test atlas's flat-
      colored region, 9-slice's actual distinguishing feature (crisp
      corners vs. stretched edges) wasn't visually distinguishable from
      a plain scaled rect, since there's no border art in that test
      asset to show it off; the slicing math itself is what the unit
      tests verify.
- [ ] Fixed-timestep + render interpolation: physics and rendering
      currently share one `dt` — smooth motion at low/uneven frame
      rates wants these decoupled.
- [ ] Basic 2D lighting: no dynamic-light concept at all today (a torch
      glow, a flashlight cone, ambient darkness) — every game that
      wants mood lighting has to fake it with `Sprite`s.
- [ ] Localization / i18n: `Text` takes a raw string with no string-
      table or locale-aware font-fallback concept — every UI string a
      game shows is hardcoded English today.
- [ ] Animation clip transitions: `AnimationSystem` hard-cuts to a new
      clip's frame 0 the instant `AnimationState.clip` changes — no
      crossfade/blend between e.g. idle and walk, which reads as a
      visible pop on faster-paced games.

### Platformer (`engine_platformer`)

- [ ] Ladders/climbing, conveyors, per-tile friction: collision is
      binary solid/one-way/slope today — no variable surface behavior.
- [x] Hitstun/knockback on damage: `damageEntity` gained optional
      `source`/`knockbackSpeed`/`hitstunSeconds` params (all `0`/`null`
      by default — disabled, original behavior unchanged). Knockback
      pushes the damaged entity directly away from `source` (both need
      a `Position`, the entity needs a `Velocity`; a zero-distance pair
      is skipped rather than dividing by zero). Hitstun sets a new
      `PlatformerController.hitstunSeconds` (counted down by a new tiny
      `HitstunSystem`, same one-job split as `HealthSystem`/
      `Health.invincibleSeconds`) that `PlatformerInputSystem` now
      checks first thing and, while `> 0`, ignores that entity's input
      entirely — movement, jump, and dash — so a knockback impulse
      isn't immediately overridden by whatever direction the player
      still happens to be holding. A no-op for an entity with no
      `PlatformerController` (e.g. a flying/AI-only enemy), matching
      this package's established "harmless if the component isn't
      there" pattern. `dealDamageOnTouch` forwards both new params and
      automatically uses the touched hazard as the knockback source.
      Verified: 12 new tests across `combat_test.dart` (knockback
      direction/magnitude, disabled-by-default, zero-distance no-op,
      `dealDamageOnTouch`'s automatic source, hitstun set/disabled/
      no-controller no-op, `HitstunSystem` countdown,
      `PlatformerInputSystem` freezing then resuming input) plus
      round-trip coverage in `component_serialization_test.dart`; full
      `engine_platformer` suite green, analyzer clean.
- [ ] Steering/avoidance among multiple AI: `PatrolBehavior`/
      `FollowBehavior`/`PathFollowBehavior` don't avoid each other, so
      packs of enemies overlap/stack.
- [x] Variable jump height (jump-cut): `PlatformerController.jumpCutMultiplier`
      (`1.0` default — disabled, original full-arc-regardless-of-hold
      behavior) + `JumpSystem` applying it. A one-shot `Velocity.y`
      clamp on the tick the jump button goes from held to not-held
      while still ascending — tracked via a new `jumpHeldLastTick`
      runtime field (compared against this tick's `jumpRequested`) so
      it fires exactly once on release instead of re-clamping every
      subsequent tick the button stays up, which is what a naive
      "not requested this tick" check would have done. Verified: 5 new
      tests in `jump_feel_test.dart` (disabled-by-default, fires once on
      release, doesn't re-fire on a later tick, doesn't fire while still
      held, doesn't fire while not ascending) plus round-trip coverage
      in `component_serialization_test.dart`; full `engine_platformer`
      suite green, analyzer clean.
- [ ] Ledge grab / mantle: no way for an entity near the top of a wall
      at the peak of a jump to grab on and climb up — every ledge has
      to be cleared by a clean jump arc today, which is a common
      "genuinely complete platformer" expectation this engine doesn't
      meet yet.
- [ ] Swimming / water physics: no water-zone concept (altered gravity/
      max-fall-speed, buoyancy, a swim state distinct from walk/jump) —
      a `TriggerZone` can detect entering water, but nothing changes
      how the entity actually moves once it has.
- [ ] Boss/enemy phase framework: `CinematicSystem` can script a
      one-shot sequence and `Health`/`damageEntity` cover generic
      combat, but there's no platformer-specific helper tying the two
      together for "at 50% health, play this cinematic beat and switch
      attack patterns" — every boss fight has to hand-roll that state
      machine from scratch today.
