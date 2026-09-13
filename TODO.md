# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

## Engine (engine_core)

- [x] Platformer physics: gravity component/system, ground detection,
      jump support, one-way platforms
- [x] Tilemaps: tile-based level representation + collision against
      tile grids (distinct from the current per-entity spatial hash)
- [x] Persistence: save/load a `World` snapshot to/from disk (builds on
      existing `toJson`/`applyPatch`)
- [x] Level lint: expose `Level.validate()` as a `game_agent` CLI
      subcommand so a level file can be checked without running the game
- [x] Particle effects: `ParticleEmitter`/`Particle`/`ParticleSystem`
      (bursts + continuous emission, scale/alpha fade over life) —
      genre-general, pure Dart (rendering lives in `engine_flutter`).

## Rendering/platform (engine_flutter)

- [x] Real sprite asset pipeline: load an actual sprite sheet image via
      `rootBundle` + `ui.instantiateImageCodec`, plus a manifest format
      for named regions (replacing the runtime-generated placeholder)
- [x] Audio: sound effect + music playback, likely via a small wrapper
      package, with an engine_core-facing abstraction like `InputState`
      has for input
- [x] Mobile input: on-screen joystick + buttons (`VirtualJoystick`/
      `VirtualButton`/`OnScreenControls`), driving the same
      `InputController` as keyboard input, auto-shown on Android/iOS via
      `GameConfig.onScreenControls`
- [x] On-screen joystick UX: `VirtualJoystick` is now floating by
      default (invisible until touched, drawn at the touch point within
      its region) instead of fixed bottom-left, fixing the
      camera-followed-player-under-the-joystick overlap. `floating:
      false` keeps the classic always-visible joystick for anyone who
      wants it.
- [x] On-screen button customization: `OnScreenButtonSpec.custom()`
      supports sprite-atlas-backed buttons (separate idle/pressed
      regions) plus full color/shape/size/border-radius/label-style
      customization for non-sprite buttons; falls back to the
      color+label rendering if no atlas/region is given or resolvable.
- [x] On-screen control feel: haptic feedback on press (buttons and
      joystick direction changes), a press-scale animation on buttons,
      and an opt-in `analogOutput` on `VirtualJoystick` exposing
      continuous `moveX`/`moveY` on `InputState` (range -1..1) for
      variable-speed movement, alongside the existing discrete actions.
- [x] Particle rendering: `EngineView` draws every `Particle` on top of
      sprites — sprite-backed (scaled by `Particle.scale`) or a plain
      colored circle, both fading via `Particle.alpha`.
- [x] Parallax backgrounds: `ParallaxLayer` component (an atlas region,
      like `Sprite`, plus a per-axis `scrollFactor`) — `EngineView`
      draws every layer first, behind tiles/sprites/particles, tiling
      across the viewport when `tileX`/`tileY` are set.
- [x] Tweening/easing helpers: `Tween`/`EasingType`/`TweenSystem` in
      `engine_core` (genre-general, pure Dart) — interpolates one
      `double` from `from` to `to` with `linear`/`easeInQuad`/
      `easeOutQuad`/`easeInOutQuad`, `loop`/`pingPong` modes, and a
      `TweenCompleteEvent` fired once for a plain (non-looping) tween.
      Deliberately doesn't write into another component itself — a game
      reads `.value` and applies it to whatever it's animating (menu
      transition, screen-shake, damage-flash), matching the rest of the
      engine's "doesn't hide how it works" approach.
- [x] Save-slot UI helpers: `SaveSlotMenuScene` (a `ButtonMenuScene`
      subclass) + `SaveSlotSpec` in `engine_flutter` — give it a list of
      slots and what selecting one should do, it checks
      `SaveGame.hasSave` per slot fresh on every `populate` and reflects
      that in each button's label. Built as a `Scene`, not a raw Flutter
      widget, since that's the pattern every other menu in this engine
      (`ButtonMenuScene`/`MainMenuScene`/`PauseMenuScene`) now follows —
      this TODO predates `Scene` existing.
- [x] Basic scene/screen management: `Scene` + `SceneController`
      (`loadScene`/`pushOverlay`/`popOverlay`) in `engine_flutter`, plus
      `GameState` for data that survives a scene switch and
      `ButtonMenuScene` for menu/pause screens — see `scene.dart`'s doc
      comment.
- [x] Cinematic support: `CinematicSystem` + `CinematicStep`
      (`WaitStep`/`CallbackStep`/`TweenStep`) in `engine_core` — a
      System like any other (`world.addSystem(CinematicSystem(steps))`),
      Flutter-free, built on `Tween`'s own easing math rather than a new
      top-level concept. Works the same for a dedicated cutscene `Scene`
      or a scripted beat inside a playable level (a door opening, a boss
      intro). (a) Input control: no new API — a game reads
      `CinematicSystem.isPlaying` in whatever gates its own input-driven
      systems, same as `pushOverlay` leaves "what an overlay shows" to
      the game. (b) Skip: `CinematicSystem.skip()` calls `skip` on the
      current + every remaining step then fires
      `CinematicCompleteEvent` immediately — an honest "jump to end
      state", not a simulated fast-forward. `TweenStep` example (a
      camera pan by moving a "camera rig" entity's `Position`) is in its
      doc comment; no dedicated camera-rig API was added since
      `Scene.cameraFollowEntity` already supports pointing at any
      entity a game chooses to animate.

## Platformer helpers (engine_platformer)

- [x] Player/enemy spawn helpers (`spawnPlayer`/`spawnEnemy`),
      `PlatformerInputSystem` (input -> move/jump), `PatrolBehavior`/
      `FollowBehavior`, `FacingSystem`/`MovementAnimationSystem` — all
      moved out of `engine_core` into a new `engine_platformer` package
      so a non-platformer 2D game isn't forced to depend on
      gravity/jump concepts
- [x] Damage/health/combat: `Health` component, `HealthSystem`
      (invincibility countdown), `damageEntity`/`healEntity`/
      `dealDamageOnTouch` helpers, `DeathEvent`. `spawnPlayer`/
      `spawnEnemy` grow an optional `maxHealth`.
- [x] Checkpoint/respawn: `Checkpoint`/`LastCheckpoint` components,
      `trackCheckpoints`, `respawnPlayer`/`respawnOnDeath` — resets
      position/velocity/health to the last touched checkpoint.
- [x] Collectible/inventory helpers: `Inventory` component (item id ->
      count), `collectItem`/`dealPickupOnTouch` helpers (mirroring
      `damageEntity`/`dealDamageOnTouch`'s pattern) + `ItemCollectedEvent`.
      `spawnPlayer` grows an optional `startingInventory`.
- [x] Updated `engine_cli`'s `default_game` template: a real
      `engine_platformer` starting point (a small tile level + player,
      `installPlatformerSystems`) instead of the old bouncing-circle
      stress-test demo. Data-driven via `Level.loadInto` +
      `main.level.json.tmpl` (the human-readable ASCII-legend `TileMap`
      form) rather than a hand-spawned `spawnPlayer` call in Dart, since
      that's the pattern the engine has settled on since this item was
      written. Not verified via an actual `game_agent create` run (pub.dev
      is network-blocked in this environment — see TODO below); the level
      JSON was validated directly against `Level.validate`/`TileMap.fromJson`,
      and the Dart mirrors patterns already browser-verified in `test_game`.

## Fully-fledged platformer engine

Gaps identified against what a genuinely complete platformer engine
needs (moving-platform feel, modern jump mechanics, a real content
pipeline, gameplay breadth, player-facing polish) — not yet started
unless marked, roughly in priority order.

- [x] Moving/kinematic platforms: `PlatformerSystem` now carries a
      resting rider along a `PlatformBody` entity's horizontal
      `Velocity` (`pos.x += platformVel.x * dt` the tick collision
      resolves "landed on top"). Vertical motion already carried a
      rider "for free" (the AABB is recomputed from the platform's
      current `Position` every tick) — only horizontal needed the fix.
      No new component: give any `PlatformBody` entity a `Velocity` and
      move it however you like (`MovementSystem`, a `Tween`, a custom
      system) and riders follow. Scoped to `PlatformBody`, not
      `TileMap`-based tiles — a whole moving tile grid is a much rarer
      case and out of scope here.
- [x] Modern jump-feel primitives: coyote time, jump buffering, double
      jump, wall jump, wall slide, and dash — all opt-in per
      `PlatformerController` field, all defaulting to the original
      strict "grounded and pressed this exact tick" behavior (every
      existing game keeps working unchanged). `collision_math.dart`'s
      `resolveSolidCircleAabb` now returns a `CollisionSide` enum
      (`top`/`bottom`/`left`/`right`/`none`) instead of a bare bool, so
      `PlatformerSystem`/`TileCollisionSystem` can derive wall contact
      from the same call that already resolved "grounded" — a real
      (pre-1.0, no external consumers) API change, not additive.
      `JumpSystem` grew coyote/buffer timers + air-jump/wall-jump
      priority; new `DashSystem` (registered by
      `installPlatformerSystems`) consumes a dash request using
      `facingSign` (now tracked by `PlatformerInputSystem`).
- [x] Sloped tile collision: `TileMap.slopeUpRightTileIds`/
      `slopeUpLeftTileIds` + `resolveSlopeCircleAabb` (`collision_math.dart`)
      + `TileCollisionSystem`. A walkable-surface simplification (floor
      height linearly interpolated across the tile), not true polygon
      physics — never blocks from underneath or the side, only resolves
      "standing on top" of the diagonal. Scoped to `TileMap` only, not
      `PlatformBody` (a rectangle has no natural ramp shape) — same
      scoping split as moving platforms, mirrored the other way.
- [x] Tiled `.tmx` import: `tileMapFromTmx` (`engine_core`, new `xml`
      package dependency — a standard XML parser, not a hand-rolled
      one) parses a **self-contained** `.tmx` (Tiled's "Embed Tileset"
      option) with **CSV**-encoded layer data into a `TileMap`. Per-tile
      bool custom properties named `solid`/`oneWay`/`slopeUpRight`/
      `slopeUpLeft` map onto the matching collision set. Scoped MVP,
      documented in its own doc comment: one tileset, one layer, no
      external `.tsx` (`source=`) support (would need file I/O this
      Flutter-free/web-targeting package doesn't do), no base64/
      compressed layer data, tile-flip flags silently stripped (base
      id imports, orientation is lost). Worth revisiting multi-layer/
      external-tileset support if a real level actually needs it.
- [x] Level preview: `game_agent lint --render <path.png>` rasterizes
      the level's `TileMap` (solid/one-way/slope tiles color-coded) plus
      a labeled marker per named entity with a `position`, using a new
      `image` package dependency. Verified visually against
      `test_game`'s real 100x36 level — staircase, both pits, one-way
      platforms, and every named entity all render correctly in the
      right place. Scoped down from "a full visual level editor" (out
      of reach for a CLI-first engine repo in one pass) to this bounded,
      genuinely useful version of the same gap.
- [x] Trigger/zone volumes: `TriggerZone` component + `installTriggerZones`
      (`engine_core`) — attach `TriggerZone(triggerId, data:)` to any
      `Position`+`Collider` entity (deliberately no `Velocity`, so
      `CollisionSystem`'s elastic swap never touches it) and a touch
      fires `TriggerEvent`. A level author now only ever needs a
      component + an id, not a bespoke `onCollisionInvolving` handler
      per zone. Found and fixed a real, more consequential bug while
      building this: `EventBus.flush()` only delivered events queued
      *before* a flush call started, so an event emitted by another
      event's handler within the same flush (exactly what
      `installTriggerZones` does, translating `CollisionEvent` ->
      `TriggerEvent`) wasn't delivered until the *next* tick — a
      one-tick lag nobody would expect. `flush()` now drains cascading
      rounds within one call (capped against a genuine handler cycle).
- [x] Pushable/dynamic physics objects: `Pushable` component +
      `PushableSystem` (`engine_core`, genre-general — Sokoban/top-down
      games want this too, not just platformers). Deliberately doesn't
      handle wall-blocking itself: it only sets `Velocity.x` from
      whether something's currently overlapping it; pair with a
      `PlatformerController` (`engine_platformer`) for a pushable that
      stops at a wall, since `TileCollisionSystem`/`PlatformerSystem`
      already do that for any physics entity — no duplicated wall logic.
      No momentum: velocity snaps to `0` the instant nothing is pushing.
- [x] Ranged/projectile combat (`engine_platformer`, alongside existing
      combat/`Health`): `Projectile` component + `spawnProjectile` +
      `ProjectileSystem` (lifetime expiry — added to
      `installPlatformerSystems`, harmless when unused like
      `HealthSystem`) + `installProjectileDamage` (on-hit damage, one
      shared `CollisionEvent` subscription for every projectile ever
      fired — `EventBus` has no per-handler unsubscribe, so a
      per-instance handler would leak one per shot over a play session).
      Excludes its own shooter via `owner`. Deliberately doesn't collide
      with level geometry (walls/tiles) — most projectiles fly straight
      unaffected by platforming physics; documented as a follow-up if a
      game actually needs it.
- [x] Remappable controls UI: `InputController.captureNextKeyDown`
      (captures the next raw key press regardless of binding, consuming
      the event so the old binding doesn't also fire) +
      `InputBindingsStorage` (save/load via `shared_preferences`, same
      cross-platform choice as `SaveGame`) + `RemapMenuScene` (a ready-
      made "press a key to rebind" menu, the `SaveSlotMenuScene`
      analogue for input — concrete, not subclassed, since every bit of
      its behavior is already a constructor parameter). One documented
      simplification: no live "press any key now" visual state on the
      tapped button — the whole menu just reloads once a key is
      captured, reading the just-updated bindings fresh.
- [x] Screen shake: `Camera.shake(magnitude, duration)` + `Camera.update(dt)`
      (a decaying random jitter offset, incorporated into `worldToScreen`/
      `screenToWorld` — the latter so a tap during a shake still
      resolves correctly). `EngineView` now calls `camera.update(dt)`
      every frame unconditionally (previously `Camera` had no per-tick
      lifecycle hook at all — only updated indirectly via `follow()`,
      which isn't even called for a static, non-following camera; a
      static camera still needs to shake on e.g. an explosion). Calling
      `shake()` again mid-shake replaces rather than stacks.

This closes out every item in this section.

## Tooling / release

- [x] Cut a `v0.1.0` git tag: `engine_flutter`/`engine_platformer`'s
      self-referencing git refs updated from `main` to `v0.1.0` (see the
      KNOWN LIMITATION comment in `packages/engine_flutter/pubspec.yaml`),
      `engine_cli`'s `create`/`upgrade` `--ref` defaults updated to match
      so a fresh `game_agent create`/`upgrade` pins to the tag instead of
      `main` by default. Tagged **locally only** — not pushed to the
      remote, so the tag doesn't exist on GitHub yet and nothing depends
      on it externally until that happens (a separate, explicit step).
      Noticed but not fixed in passing: `upgrade`'s regex only rewrites
      the `engine_core:` ref in a generated project's pubspec.yaml, not
      `engine_platformer:`'s — pre-existing gap, worth its own TODO if
      `engine_platformer` ends up in the default template's dependency
      list (it now is, see the template-update item above).
- [ ] Publish `engine_core`/`engine_flutter`/`engine_cli` to pub.dev —
      removes the git-ref-matching constraint entirely via normal semver
- [ ] Test on a real Android/iOS device (or at least a release build) —
      everything so far has only been verified on Flutter web debug
      builds; orientation lock, lifecycle pause/resume, and real-world
      performance are unverified outside that

## New engine features

Gaps identified in a follow-up "what tools/systems are missing now"
pass, checked directly against the code (not from memory) — none of
this existed anywhere in `engine_core`/`engine_flutter` at the time
these were written. Roughly priority-ordered by how load-bearing each
is for everything else.

- [x] Text rendering: `Text` component (`engine_flutter`) — drawn fresh
      every frame via `TextPainter` in `EngineView`, `screenSpace: bool`
      chooses world-space (scrolls/zooms with the `Camera`, e.g. a
      damage number) vs. screen-space (fixed viewport pixels, e.g. a
      HUD score — the primitive the still-open HUD/UI item below needs).
      Aliased as `txt.Text` inside `engine_view.dart` and documented to
      collide with Flutter's own `Text` widget — a consumer importing
      both `engine_flutter` and `material`/`widgets` needs `hide Text`
      on one side, same precedent `Velocity`/`Action` already set.
      Verified in the browser: added a live `Coins: N` HUD readout to
      `test_game`'s `MainScene`, confirmed it renders at a fixed screen
      position regardless of camera movement.
- [ ] Debug visualization: the fps/tick overlay exists, but there's no
      way to *see* what the physics is doing — no collider/AABB outline
      draw, no tile-collision-bounds visualization, no spatial-hash
      grid overlay. Every physics bug found this session got diagnosed
      by hand-deriving coordinates and adding print statements; a
      debug-draw toggle would have caught several of them instantly.
- [ ] Raycasting: no ray-vs-tile or ray-vs-entity query exists anywhere
      — useful standalone (line-of-sight checks, ground/wall probes,
      hitscan weapons) and a direct prerequisite for AI depth below.
- [ ] AI depth: only `PatrolBehavior`/`FollowBehavior` exist — no
      steering behaviors, no vision-cone/line-of-sight gating (an enemy
      "follows" through walls today), no pathfinding (no A*/navmesh at
      all), so any enemy smarter than "patrol a fixed range" or "chase
      in a straight line regardless of obstacles" has to be hand-built
      from scratch.
- [ ] HUD/UI framework: `ButtonMenuScene` covers menus; nothing covers
      persistent in-game UI (health bar, minimap, inventory display) —
      blocked on text rendering above, and even with that, no
      screen-space (as opposed to world-space/camera-relative) render
      concept exists yet.
- [ ] Restructure each package's `lib/src/` by concern (e.g.
      `physics/`, `rendering/`, `logic/`/`ai/`, `ui/` — `engine_flutter`
      already has a `ui/` folder as precedent) instead of the current
      flat `components/`/`systems/` split with everything else loose at
      the top level. A real refactor (import-path churn across every
      package and `test_game`), not a feature — do it as its own
      focused pass once the current feature-adding streak settles down,
      not interleaved with it.

## Validation

- [x] Build one real (small but complete) game on the engine —
      `test_game` (local-only, gitignored): tile-based platformer
      physics, keyboard-controlled player, patrolling AI enemy,
      collectible coins, camera-follow, all via `engine_platformer`'s
      helpers
- [x] Test coverage: `engine_core`/`engine_flutter`/`engine_platformer`
      all at 100% line coverage (`dart test --coverage` /
      `flutter test --coverage`). `engine_flutter`'s
      `audio_manager.dart` is a deliberate, documented exception
      (`// coverage:ignore-file` — see that file's comment).

## Performance

- [x] Benchmark suite: `package:benchmark_harness` benchmarks added
      under `packages/engine_core/benchmark/` (`world_step`,
      `collision_system`, `particle_system`, `entity_churn`) and
      `packages/engine_platformer/benchmark/` (`tile_collision`,
      `full_pipeline`) — see each package's README for how to run
      them. A baseline for the items below and for future speed work in
      general; re-run before/after a perf-motivated change to check it
      actually helped.
- [x] **Fixed real bug**, found by `entity_churn_benchmark.dart`
      crashing with a `RangeError` on its first run:
      `ComponentStore.remove` left a dangling `_entityToDense` entry
      when removing an entity that was the *only* (or last) one in that
      store's dense array — `lastEntity` in that case equals the entity
      already being removed, so the old code re-inserted the mapping it
      had just deleted, pointing at an index the very next
      `_dense.removeLast()` made invalid. A later `set()` on a *recycled*
      entity id (exactly what `EntityManager` does under sustained
      spawn/destroy churn) would then write past the end of `_dense`.
      Fixed in `packages/engine_core/lib/src/component_store.dart`, with
      a regression test in `component_store_test.dart`. This means
      before this fix, **any game destroying entities under load could
      have silently corrupted component data or crashed** the moment a
      recycled id collided with this stale-index case — worth
      remembering as the reason `entity_churn_benchmark.dart` stays in
      the suite even though nothing is currently being optimized there.
- [x] **Fixed (partial) + real correctness bug found**: `CollisionSystem`
      used a fixed default `cellSize` (24) regardless of actual
      `Collider.radius`. Beyond the performance cost this TODO
      originally flagged, that was also a **latent correctness bug**:
      `SpatialHash.forEachNearbyPair` only checks same/adjacent cells,
      which only catches every colliding pair when `cellSize >= ` the
      largest `radiusA + radiusB` that can occur — a fixed 24 could
      silently miss real collisions between two colliders each bigger
      than radius 12. Fixed by auto-sizing `cellSize` every tick to
      `2 * ` the largest `Collider.radius` currently in the world
      (always satisfies that bound; `CollisionSystem(cellSize: ...)`
      still accepts an explicit override for a profiled special case).
      Regression tests in `collision_system_test.dart` cover both the
      correctness fix (a large-radius pair a small fixed cellSize would
      have missed) and the miss itself (with an explicit too-small
      `cellSize`, to document the failure mode auto-sizing avoids).
      Benchmarked improvement (this machine, `collision_system_benchmark`,
      radius-4 colliders so auto-sized cellSize=8 vs. the old fixed 24):
      n=100 ~320us -> ~188us (~1.7x), n=1000 ~4.56ms -> ~1.74ms (~2.6x),
      n=5000 ~1.11s -> ~0.57s (~1.9x).
      **Not fully fixed**: at n=5000 the benchmark still shows
      superlinear cost, but this is now understood to be inherent to a
      uniform-grid spatial hash under extreme physical clustering (the
      benchmark's entities pile up at the world edges via
      `MovementSystem`'s bounce, which no `cellSize` choice fixes —
      cells at genuinely maximum occupancy still cost O(k^2) each). A
      real fix for that residual case needs a fundamentally different
      broad-phase (cell subdivision, a BVH) — worth a future TODO item
      if a real game hits it, not undertaken here since it's a much
      bigger change for a scenario no current game has actually hit.
- [x] **Fixed**: `ComponentStore`'s sparse side was a
      `Map<EntityId, int>`, paying hashing/boxing overhead on every
      `get`/`set`/`has`/`remove` (the hottest path in the engine) for
      no reason — `EntityId` is a small, densely-recycled `int`.
      Replaced with a `List<int>` indexed directly by entity id (`-1` =
      absent, grown on demand, never shrinks — the standard sparse-set
      tradeoff). Behavior-preserving (same swap-remove logic, same fix
      for the dangling-index bug above, all existing tests pass
      unchanged). Measured with the benchmark suite, before -> after on
      this machine: `world_step_benchmark` n=5000 ~1010us -> ~391us
      (~2.6x), `entity_churn_benchmark` n=5000 ~18.2ms -> ~12.2ms
      (~1.5x), `collision_system_benchmark` n=5000 ~2.5s -> ~1.1s
      (~2.3x — the remaining cost there is the density issue below,
      unrelated to this fix), `particle_system_benchmark`
      emitters=500 ~1.47ms -> ~0.82ms (~1.8x).
- [x] **Fixed**: `EventBus.flush` dispatched via
      `Function.apply(h, [event])`. Replaced with handlers stored as
      `void Function(Object)`, wrapping the `as T` cast in a closure
      created once at `on<T>` registration time instead of per
      dispatch — a direct, inlinable call site instead of the slower
      dynamic-invocation path `Function.apply` goes through.
      Behavior-preserving (all existing tests pass unchanged).
- [x] **Fixed**: `EngineView`'s sprite pass did one
      `canvas.save()`/`translate()`/`scale()`/`drawImageRect()`/
      `restore()` *per sprite*, every frame. Sprites with uniform
      positive scale (the common case) now batch into one
      `Canvas.drawAtlas` call per shared atlas image instead — no
      per-sprite canvas state changes. `RSTransform` (what `drawAtlas`
      takes per sprite) only supports one positive, uniform scale
      factor, so a sprite with `scaleX != scaleY` or a negative scale
      (the standard `FacingSystem` horizontal-flip pattern) falls back
      to the original per-sprite path. `sprite_rendering_test.dart`
      covers both paths and mixed-atlas rendering; 100% coverage held.

## Features (engine_flutter)

- [x] Z-index / draw order: `Sprite`/`ParallaxLayer`/`TileMap`/
      `Particle` (via `ParticleEmitter.zIndex`) all gained a `zIndex`
      (int, default 0) — `EngineView` now sorts every renderable by it
      before drawing, with the engine's original fixed order (parallax,
      tiles, sprites, particles) as the tie-break so a game that never
      sets `zIndex` renders identically to before. Sprite atlas batching
      (the `drawAtlas` item above) still applies *within* a `zIndex`.
      See `engine_flutter`'s README "Draw order (z-index)" section.
      `z_index_test.dart` covers defaults, round-trips, and actual
      reordering (a negative-`zIndex` sprite drawing behind a
      default-`zIndex` `ParallaxLayer`/`TileMap`); 100% coverage held
      across `engine_core`/`engine_flutter`.
- [ ] **Not done — real masking/clipping**: z-index only reorders draw
      *calls*; it has no clip-path or blend-mode primitive, so it can't
      express "this shape cuts a hole in what's behind it" or "this
      layer only shows through a mask shape." A real masking feature
      would need its own API (e.g. a `Mask`/`ClipShape` component and a
      `Canvas.clipPath`/`saveLayer`+`BlendMode.dstIn` pass in
      `EngineView`) — worth doing once there's a concrete use case
      (e.g. a fog-of-war reveal, a vignette, a wipe transition).
- [x] **Evaluated — no action needed yet**: `WorldView.nearestWithPosition`
      is O(n) per call, so O(n²) per tick in the worst realistic case
      (every entity is AI-driven and queries once per tick) — measured
      via `benchmark/world_view_benchmark.dart`: ~0.06ms/tick at 50
      simultaneous queriers, ~0.7ms/tick at 200, ~14.4ms/tick at 1000
      (already most of a 60fps frame budget on its own). Confirms the
      doc comment's existing caveat with real numbers rather than
      leaving it a guess: fine for a typical platformer's AI entity
      count (tens to a couple hundred), a real cost only once a game
      has many hundreds of simultaneously-querying AI agents. No fix
      applied — `SpatialHash`-backed nearest-neighbor is still the
      documented remedy if a game actually hits that scale.
