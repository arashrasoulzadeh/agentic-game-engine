# Changelog

All notable changes to this project are documented in this file, newest
first. `v0.1.0` is tagged locally (see [TODO.md](TODO.md)) but not yet
pushed to the remote or published to pub.dev — still consumed via the
self-referencing git-dependency pattern documented in each package's
pubspec.yaml.

## [Unreleased]

### Performance (round 4)

- Particle rendering: plain (spriteless) particles now batch through
  one `Canvas.drawAtlas` call per `zIndex` via a new tiny cached
  `ParticleDotTexture`, instead of one `drawCircle`/`Paint` pair per
  particle — the same win `_collectSpriteItems`'s existing sprite
  batching already gets, now applied to the same shape of problem for
  particles (a single torch alone can have 30-50 active at once).
  Falls back per-particle to the original `drawCircle` path for any
  frame before the texture's one-time async generation resolves
  (typically within the first frame or two) or for a particle that
  carries its own registered `Sprite`. A real pixel-sampling test
  proves multiple batched particles still render at their own distinct
  position/color, not just "doesn't crash."
- `_collectParticleItems` no longer does a `Sprite` component-store
  lookup per particle when nothing in the world has a `Sprite`
  attached to a particle entity at all (the common case, since
  `ParticleSystem` itself never attaches one) — checked once per frame
  instead of once per particle.
- `AnimationClip.sequence` is now memoized by its full argument set —
  a call site that rebuilds the same sequence repeatedly (e.g. from
  `Scene.populate`, which reruns on every scene reload/room
  transition) gets the same cached instance back instead of
  re-running `List.generate`/reallocating a fresh clip every time.

### Performance (round 3, unverified — see TODO.md)

- `Light2D.useGpuShadows`'s GPU shadow pass now composites with
  `BlendMode.screen` instead of `BlendMode.plus` — a candidate fix for
  the known multi-light oversaturation bug (a mechanistically-explained
  hypothesis: the shader's `falloff()` plateau draws a fully opaque
  disc over 60% of a light's radius, and unbounded `plus` let two such
  discs overlapping saturate to solid white). `screen` is bounded and
  mathematically can't do that. Zero live risk — `useGpuShadows`
  still defaults `false`, `test_game` still doesn't enable it — but
  **not yet confirmed fixed on a real device**; see TODO.md before
  relying on this.

### New engine features (round 4)

- `Gravity.fallMultiplier`: an extra gravity multiplier `GravitySystem`
  applies only while an entity is already falling (`Velocity.y > 0`),
  independent of `Gravity.scale` (which speeds up rise and fall
  equally, changing jump height/reach too). The standard "floaty rise,
  snappy fall" platformer feel — `1` (default) is no asymmetry,
  identical to every jump before this field existed.
- `ParallaxLayer.fitHeight`: stretches a background region to exactly
  the viewport's height instead of native size (optionally tiled).
  Existing tiling (`tileY`) only looks right for art authored as a
  seamless repeatable strip — repeating a one-off painted vista (its
  own full sky-to-ground composition) stacks visibly duplicate copies
  of the whole scene. `fitHeight` guarantees full coverage for that
  kind of art regardless of viewport size, at the cost of a non-uniform
  stretch. Found via a real content bug: a level's background mural,
  native-sized and centered, only covered part of the viewport,
  leaving a gap; naively enabling `tileY` "fixed" the gap but
  duplicated the whole scene instead.
- Melee (sword) and ranged (gun) combat: a new `Weapon` component
  (`WeaponKind.melee`/`ranged`, damage, cooldown, range/speed) plus
  `AttackSystem`, which fires on an `"attack"` input action or a
  directly-set `attackRequested` (for AI/touch-button use). Both kinds
  reuse the already-shipped `spawnProjectile`/`installProjectileDamage`
  — a melee swing is a zero-velocity, short-lived projectile positioned
  ahead of the attacker, so no new hitbox/collision machinery was
  needed.
- Positional/spatial audio: `AudioManager.playPositionalSound` pans and
  attenuates a one-shot SFX by distance from a listener position (the
  camera, typically), via a new pure `positionalAudioParams` helper —
  computed once at trigger time, not tracked live per frame.
- Tilemap auto-tiling: `TileMap.withAutotile` resolves a designer's
  single placed "wall" tile id into the correct edge/corner sprite
  variant per cell, via the standard 4-bit neighbor bitmask
  (`autotileBitmask`) — a load-time transform, so `EngineView`'s
  per-frame tile rendering needed zero changes.
- `SaveGame.listSlots()` enumerates every slot with a save currently
  stored, for a slot-picker UI that doesn't want to hardcode slot names
  up front.
- Gamepad support: `GamepadController` maps generic button/axis ids
  (matching the W3C standard gamepad button order) to the same logical
  actions keyboard and touch already write into `InputState` — the
  transport-agnostic binding layer any gamepad plugin's raw callbacks
  can wire into. `GamepadBindingsStorage` persists button bindings the
  same way `InputBindingsStorage` does for the keyboard.
- `game_agent lint --playable`: flood-fills a level's non-solid tiles
  from its spawn entity and reports any other entity not reachable —
  catches an item/exit sealed off behind solid tiles that plain
  schema validation can't see.

### Bug fixes (round 2)

- **A dusk/night `DayNightCycle` scene rendered brighter than its
  configured `ambientBrightness`**: `ambientColorArgb` held hand-
  darkened hues on a schedule independent of `timeOfDayBrightness`,
  so a still-bright color composited at a brightness-driven alpha —
  visually confirmed as a dark dome that failed to actually darken the
  revealed area around the player's own light. Fixed with two scaling
  passes: `DayNightCycle.ambientColorArgb` now scales its hue toward
  black by `timeOfDayBrightness` before weather blending, and
  `EngineView._effectiveAmbientColorArgb` does a second pass toward
  black by the scene's own `ambientBrightness` (a multiplier
  `DayNightCycle` has no way to know about on its own). Verified via a
  real pixel-sampling regression test mirroring dusk +
  `ambientBrightness: 0.25`.

### Performance (round 2)

- `Light2D.shadowEdgeSoftness` defaults to `8`, not `0` — a torch with
  no explicit value in its level JSON was still paying for a real
  `MaskFilter.blur` on its shadow-casting reveal paint. Proven via a
  controlled, screenshot-only on-device A/B (identical input recipe
  both times) to be the dominant raster-thread cost for a scene with
  several shadow-casting lights on screen at once: **raster avg
  3.0ms→1.7ms, max 5.7ms→2.6ms** with it set to `0` — a ~45-55%
  reduction. No engine code change; a level-authoring fix.
- New diagnostics for finding costs like the one above without a full
  DevTools session: `FrameStats.onSpike`/`spikeThresholdMs` (fires the
  instant a frame exceeds a threshold) and
  `EngineView.showPerformanceOverlay`/`GameConfig.showPerformanceOverlay`
  (Flutter's own raster/UI-thread bar-graph widget, wired end to end
  through `GameRunner`).
- `EngineView`'s whole ambient-lighting pass is now skipped when the
  resulting darkness would round away to fully transparent anyway
  (`ambientBrightness` above a `1 - 0.5/255` threshold, the exact
  8-bit alpha-rounding boundary) — zero visual risk, since the skipped
  work would have been invisible regardless.
- A concrete, mechanistically-explained (not yet device-confirmed)
  hypothesis for the `Light2D.useGpuShadows` oversaturation bug is now
  recorded on its own doc comment and in `TODO.md`: `light_shadow.frag`'s
  `falloff()` is flat at full strength out to 60% of a light's radius,
  drawing a fully opaque white disc there for an untinted light,
  composited with unbounded `BlendMode.plus` — two such plateaus
  overlapping (ordinary torch spacing) saturates the overlap to solid
  white well before any third light contributes.

### Performance

- `pack-assets` now bin-packs with a real MaxRects (Best Short-Side-Fit)
  algorithm instead of a row/shelf packer — noticeably denser output for
  a mixed-aspect-ratio sprite set, since a shelf packer wastes space
  sizing every row by its tallest item.
- `EngineView`'s debug overlays (`showColliderDebug`) now batch every
  collider circle into one `Path`/`drawPath` call and every tile border
  into one `Path` per collision kind (solid/one-way/slope), instead of
  one `drawCircle`/`drawRect` per collider/tile.
- New `AtlasRegistry.unregister(id)` actually disposes an atlas's
  decoded `ui.Image`, releasing its GPU texture — the registry
  previously had no way to release memory for an atlas a game is done
  with (e.g. after leaving a room for good).
- `CollisionSystem` now reuses one `SpatialHash` instance across ticks
  (rebuilt only when cell size or world width changes) instead of
  constructing and discarding a fresh one every `update()`.
  `SpatialHash` itself was rewritten with an active-key list + a
  recycled-bucket pool so `clear()` no longer needs to drop and
  reallocate its cell map every tick, while still bounding it to only
  cells touched in the current cycle (an earlier "empty buckets in
  place" attempt at this same fix regressed n=100 collision-tick cost
  3-4x, caught by `collision_system_benchmark.dart`, because it let
  every cell an entity had *ever* visited stay resident forever).
- `pack-assets` gained a `--scales` flag: pack the same source images
  at multiple resolution tiers (e.g. `--scales 0.5,1.0,2.0`), writing
  each tier with Flutter's own `@<scale>x` asset-variant suffix
  (`atlas@0.5x.png`) so a game can ship low/high-DPI variants without
  a second packing pass.
- `AudioManager.playSound` now pulls from a small pool of reused
  `AudioPlayer`s instead of constructing a new one per call.
- New opt-in `Light2D.cacheShadowGeometry`: when a shadow-casting
  light's position/radius/cone/ray-count/etc. are all bit-identical to
  the previous frame, `EngineView` reuses last frame's raycast-sweep
  distances instead of re-running it — a cache hit is pixel-identical
  to the uncached path, a miss invalidates completely and immediately
  (no interpolated lag, unlike the reverted `shadowSmoothingSeconds`
  approach). Off by default; doesn't detect `TileMap` content changes,
  so a game enabling it near destructible geometry must force
  invalidation itself.

### Asset packing

- New `game_agent pack-assets` command (`engine_cli`): recursively
  scans a directory of level image assets and packs them into one
  sprite sheet PNG + a region manifest, written in the exact
  `{"regions": {"name": {"x","y","w","h"}}}` shape
  `SpriteAtlas.fromManifest` (`engine_flutter`) already reads — no new
  loading code needed on the consuming side. Run it as a pre-build step
  ahead of `flutter run`/`flutter build` instead of loading one
  `SpriteAtlas` per source sprite at runtime.
- New `GameConfig.packedAtlasId`/`packedAtlasImage`/`packedAtlasManifest`
  (all `null` by default — no behavior change for an existing game):
  `GameRunner` auto-registers the packed atlas into every loaded
  `Scene`, decoding it once and reusing that same `SpriteAtlas` across
  scene switches rather than re-decoding per load; a scene that already
  registers something under the same id wins over the auto-
  registration, not clobbered by it. Gated by a new compile-time
  `usePackedAtlas` flag (`--dart-define=USE_PACKED_ATLAS=false` to fall
  back to per-scene loading while iterating on art) — the literal
  "build flag" mechanism requested.

### Bug fixes

- **`grounded` flickered false every other tick while resting on solid
  ground**: `resolveSolidCircleAabb`'s overlap test used `distSq >=
  radius * radius` to mean "no overlap," but an entity resolved to
  rest exactly on a surface (`pos.y = top - radius`, set by the very
  same function) sits precisely on that boundary — `>=` treated
  "touching" as "not touching," so `grounded` (reset every tick by
  `PlatformerSystem`, only re-set additively by a fresh detection)
  read false every other tick once settled: `GravitySystem` saw the
  false tick and nudged `vel.y` up, `MovementSystem` moved the entity
  a fraction of a pixel into the surface, and the next tick's
  detection caught it and snapped back — invisible in position, but
  very visible in `grounded` itself. With `JumpSystem`'s default
  `coyoteTimeSeconds: 0`, a jump only fires on an exact grounded tick,
  so roughly half of all jump presses while standing still were
  silently dropped; anything driving a falling/idle animation off
  `!grounded` flickered every other frame. Fixed by making the check
  strictly `>` — found live via a temporary debug readout in
  `test_game` showing `grounded: false` with `vy: 0.0` and an
  unchanging `y`, i.e. genuinely at rest, not actually falling.
- **A non-solid `TileMap` tile (e.g. `ladderTileIds`) rendered
  identically to a solid one**: `_collectTileMapItems`'s color lookup
  only special-cased `oneWayTileIds`/slope ids, so anything else —
  including a ladder, which the physics correctly treats as fully
  walk-through — fell through to the same opaque solid-tile gray as an
  actual wall. Visually indistinguishable from a real wall standing
  right next to the player. Ladder tiles now get their own translucent
  tan, matching the "translucent = passable" convention `oneWayTileIds`
  already established.
- **`LadderSystem` zeroed a jump's `Velocity.y` just from touching a
  ladder tile, even without pressing up/down**: it engaged climb
  override — `vel.y = 0` (or a climb speed) and `grounded = false` —
  on any `onLadder` overlap, regardless of input. A jump arc that
  merely passed through or near a ladder tile (or, as in `test_game`,
  a coin placed inside the ladder's own tile column, so jumping toward
  the coin necessarily crosses it) had its vertical velocity silently
  killed the instant the collider touched the tile, well before the
  player ever meant to grab the ladder — read live as "jump/falling is
  broken near the first coin." Now only engages while up or down is
  actually held that tick; a jump through/near a ladder is completely
  unaffected, and letting go of up/down mid-climb now stops overriding
  `vel.y` (lets gravity/whatever else apply) instead of freezing in
  place.
- **Shadow-casting lights flickered while moving**: `raycastTileMap`'s
  grid DDA traversal picked which axis to step with a strict `<`
  comparison between `tMaxX`/`tMaxY` — for a ray passing near a
  tile-grid corner (always true for *some* ray, since shadow-casting
  samples all the way around a light) those two values nearly tie, and
  which one a continuously moving light's position made momentarily
  smaller could flip from one frame to the next, changing whether a
  corner-adjacent solid tile blocked the ray. Now steps both axes
  together whenever they're within a small epsilon, treating the ray
  as passing exactly through the shared corner — deterministic
  regardless of a sub-pixel origin move.
- **Tilemap tiles rendered as flat placeholder colors, with no way to
  show real textures**: new `TileMap.atlasId`/`regionByTileId` let
  `EngineView` draw a tile id's actual atlas region instead of its
  debug color — `test_game`'s level now shows real dirt texture on its
  ground/platforms instead of flat gray blocks.

### Lighting quality

- **One-way platforms never blocked light/shadows**: new opt-in
  `Light2D.blockOneWayPlatforms` (`false` default) threaded into the
  shadow-casting raycast — a one-way platform renders as an opaque-
  looking surface but let light shine straight through by default;
  set it per light that's actually near one.
- **Flat/artificial, then "cartoony," then still-too-hazy light
  falloff + hard, faceted shadow edges**: three iterations landed on a
  *plateau* shape — full strength held flat out to 60% of the radius
  (the light's body reads as a real, solidly-lit area) then falling
  off only over the remaining 40% — instead of a curve that dims from
  the very center, however smooth. Softness now lives only at the
  edge, not smeared across the whole light. A shadow-casting/cone
  light's visibility-polygon edges get a blur (once per light per
  frame, not per sampled ray, so it costs nothing extra as
  `shadowRayCount` scales) instead of a hard cutoff, driven by a new
  configurable `Light2D.shadowEdgeSoftness` (default bumped from an
  initial `3` to `8` — reported live as too subtle to read as soft at
  all against a typical light radius).
- **A light attached to a moving entity didn't follow fixed-timestep
  interpolation**: `_drawLighting` now runs each light's position
  through the same `_interpolated` blend `Sprite`/`Particle` rendering
  already uses whenever `EngineView.fixedTimestepSeconds` is set — a
  light used to visibly lag/step relative to its own entity's smoothly-
  interpolated sprite; a no-op when fixed-timestep isn't in use.
- **Only `TileMap` geometry cast shadows**: new opt-in
  `Collider.blocksLight` (`false` default) — a shadow-casting light's
  per-ray raycast now also checks every light-blocking `Collider`
  (crates, pillars, closed doors — any solid prop not baked into the
  tile grid), taking whichever hit (tile or collider) is nearer, the
  same way multiple `TileMap`s already merge.
- **Overlapping lights didn't add brightness**: new opt-in
  `Light2D.overbrightIntensity` (`0` default) — a separate, plain-white
  additive (`BlendMode.plus`) glow pass against the real scene colors,
  independent of the brightness-reveal pass (which alone can only ever
  erase darkness back to "fully revealed," never past it). Two
  overlapping lights with this set now genuinely stack brighter.
- **A light revealed open air, not just surfaces**: new
  `Light2D.openAirFalloffScale` (`1.0` default) — for a shadow-casting
  light, any ray that travels its *entire* radius unobstructed
  (genuinely open air, e.g. sky above an outdoor level) is pulled in to
  `radius * openAirFalloffScale`; a ray that hits a real surface short
  of the radius is left untouched either way, so a light still fully
  illuminates whatever it's actually next to.
- **Shadow flicker while the light source moves**: root cause was the
  grid-raycast tie-break jitter (see above), already fixed there. A
  same-round attempt at an additional smoothing layer
  (`Light2D.shadowSmoothingSeconds`, exponentially blending each ray's
  distance toward its raw value over time) turned out to read as the
  shadow visibly *lagging*/animating into place instead of tracking
  the light exactly — reported live as "animating instead of casting
  real." Real light has zero transition delay, so `test_game`'s player
  light no longer sets it; the field stays available (`0` default,
  opt-in) for a game that deliberately wants that softened look, but
  the tie-break fix is the actual correct fix for the flicker.
- **Frame-rate cap**: new `EngineView.maxFps`/`GameConfig.maxFps`
  (`null` default, uncapped) skips a ticker callback outright when it
  arrives sooner than `1 / maxFps` since the last processed one — a
  stable, platform-independent simulation/render rate instead of
  however fast a given display happens to run.
- **`maxFps` cap read as uneven/"not solid" rather than a clean rate**:
  the throttle compared each raw callback's timestamp against the
  *last processed* callback's own (jittery) timestamp — on a display
  whose refresh interval isn't an exact multiple of `1 / maxFps` (a
  90Hz or 120Hz phone capped to 60fps, reported live: "why cant be
  solid 60"), that produces alternating real frame gaps (e.g. ~11ms
  then ~22ms on 90Hz→60fps) even though the long-run average genuinely
  hits the target rate — visible as uneven pacing, not a real dropped
  frame. Fixed by scheduling against a virtual clock (`_nextTickDue`)
  that advances by exactly `1 / maxFps` every processed frame instead
  of re-anchoring to wherever the last raw callback happened to land;
  a stall (app backgrounded) resyncs the virtual clock to now rather
  than bursting through a backlog. New regression test in
  `fixed_timestep_test.dart` asserts every processed `dt` stays within
  6ms of the 60fps target under simulated 90Hz raw callbacks — a
  skip-based scheme fails this by alternating ~11ms/~22ms gaps.
- **A light always affected the whole screen regardless of any
  entity's `zIndex`** (reported live: "if light emitted from character
  z-index and not in z-index of that object why it should affect it"):
  the ambient-darkness pass was one full-screen darken-then-reveal
  layer drawn after every sprite, with no concept of z at all. New
  opt-in `Light2D.minZIndex`/`maxZIndex` (both `null` by default — no
  restriction, identical to the original behavior at no extra cost)
  scope a light to a z-band; `EngineView` implements this by splitting
  the z-sorted draw list into bands at every light's z boundary and
  compositing each band's own darkness/reveal pass in isolation before
  the next band draws on top, so a torch scoped to the ground layer
  can no longer bleed light onto a foreground overlay or background
  parallax layer sitting at a different `zIndex`. Real bug caught only
  by a genuine pixel-sampling test (not the usual "renders without
  crashing" pattern): each band's darkness rect was unconditionally
  full-screen, so a *later*, unlit band's rect painted solid black
  over the *entire* accumulated canvas, silently erasing every earlier
  band's already-revealed content. Fixed by compositing a banded
  darkness pass with `BlendMode.srcATop` instead of the default
  `srcOver`, so it only darkens pixels that band already drew into,
  leaving the rest of its layer transparent (a no-op against whatever
  other bands composited before or after it).

### Masking & clipping

- New `ClipShape` component (`engine_flutter`): a circle or rect,
  `reveal` mode (only show the scene through the shape — a spotlight/
  peephole/wipe transition) or `cutout` mode (punch a hole through the
  already-drawn scene — a vignette). `reveal` clips forward via
  `Canvas.clipPath` around the whole draw body; `cutout` erases
  backward via a `saveLayer` + `BlendMode.dstOut` pass, since a
  `Canvas` is immediate-mode and can't retroactively mask pixels
  outside a layer it still owns.

### Cinematic camera & screen effects

- `CameraPanStep`/`CameraZoomStep`/`CameraShakeStep`/
  `CameraFollowStep` (`engine_flutter`): `CinematicStep` implementations
  driving a `Camera` directly — pan/zoom capture their *from* value at
  `start()` so steps chain without hand-tracking the previous step's
  endpoint; `CameraShakeStep` just fires `Camera.shake()` once and
  holds the sequence for its duration (`Camera.update` already runs
  every frame regardless); `CameraFollowStep` continuously re-centers
  on a moving target for one cinematic beat (a fleeing enemy), distinct
  from `Scene.cameraFollowEntity`'s whole-scene, hard-snap-every-tick
  following. Live purely in `engine_flutter`, not alongside
  `CinematicStep` in `engine_core` — `Camera` is a rendering-only
  concept with no ECS/`World` presence, and a step needs a direct
  reference to the actual `Camera` instance `EngineView` renders with.
- New `ScreenTint` component + `ScreenTintStep`: a full-screen color
  overlay (alpha channel is strength, same convention as
  `Light2D.colorArgb`) for fades and impact flashes. Real bug caught
  by live testing, not unit tests: two independent `ScreenTintStep`s
  chained as a flash (up then down) each spawned their *own*
  `ScreenTint` entity by default, so the "up" step's entity was left
  stuck at its peak alpha forever once its own step completed — a
  persistent, wrong-looking tint for the rest of the cutscene, since
  nothing ever animated *that* entity back down. Fixed with a mutable,
  shareable `entity` constructor parameter so two steps can be pointed
  at one entity spawned up front; regression tests cover both the bug
  (unshared — stuck alpha) and the fix (shared — resets correctly).
- A `Scene` using any of these must leave `cameraFollowEntity` at its
  default `null` — `EngineView` hard-snaps the camera to a followed
  entity's `Position` *every* tick when set, which would immediately
  undo whatever a cinematic step just did that same tick.
- Second real bug caught only by live testing: a `Scene` referencing
  its own `Camera` field inside `populate()` (to build cinematic
  steps referencing it) threw `LateError: Field has not been
  initialized` — `Scene`'s documented lifecycle runs `populate()`
  *before* `createCamera()`, so a `late Camera` field assigned inside
  `createCamera()` doesn't exist yet when `populate()` needs it.
  Surfaced only as an uncaught console promise rejection and an
  infinite loading spinner, no visible error overlay. The general
  fix for any `Scene` in this position: initialize the field at
  declaration instead of inside `createCamera()`, which just returns it.
- `test_game`'s new `CinematicDemoScene` (gitignored, not part of this
  package) exercises the whole set: fade in, pan across a set, punch
  in with a shake + red flash, pull back out, follow a fleeing enemy,
  fade to black — reachable from the main menu's new "CINEMATIC DEMO"
  button.

### v1.0 release readiness

- **`LICENSE`**: MIT, at the repo root and in each of the four
  packages; `homepage`/`repository` added to every `pubspec.yaml`.
- **Malformed-input robustness**: `ComponentRegistry.applyToEntity`/
  `World.applyPatch` (the entity-patch-JSON entry points behind
  `Level.loadInto`, `SaveGame.load`, and direct `applyPatch` calls) now
  throw clear, catchable `ComponentApplyException`/`WorldPatchException`
  on malformed input instead of a bare `TypeError`. `SaveGame.load`
  also guards a corrupted (non-object) save the same way.
- **API stability commitment**: root `README.md` now documents the
  semver contract each package makes starting at `1.0.0` (its
  top-level export surface only, `src/` internals stay free to move),
  and explicitly keeps the `Text`/`Velocity`/`Action` Flutter-name-
  collision `hide` workaround as a permanent, deliberate decision.

### New engine features (round 2)

Working through TODO.md's "New engine features (round 2)" section, one
item at a time.

- **Multi-component query helper**: `WorldView.entitiesWithAll<A, B>()`
  — every entity carrying both component types, in no particular
  order, without hand-nesting a loop plus null-checks at the call site.
- **Variable jump height (jump-cut)**: `PlatformerController.jumpCutMultiplier`
  (opt-in, off by default) + `JumpSystem` — a one-shot `Velocity.y`
  clamp the tick the jump button is released while still ascending, for
  a short hop vs. a full jump from one input.
- **Spatial range queries**: `WorldView.entitiesWithinRadius(x, y,
  radius, {exclude})` — every entity with a `Position` within range,
  for AI perception / area-of-effect queries.
- **Deterministic RNG + replay/record**: `DeterministicRandom` (a
  seeded, resettable RNG wrapper) plus `ReplayRecorder`/`ReplayPlayer`
  for capturing and replaying a timestamped sequence of arbitrary JSON
  snapshots (input, agent actions, etc.) — both needed for
  reproducible testing/debugging of an agent-driven or physics-heavy
  game.
- **Content hot-reload**: `LevelHandle` re-loads a level JSON file into
  a running `World` — tracks every entity a level spawned and tears
  down exactly those before applying an edited version, validating the
  new JSON first so a malformed edit leaves the previous, working level
  untouched instead of tearing it down for a load that fails.
- **Multi-layer / animated tiles**: `TileMap.backgroundTiles`/
  `foregroundTiles` (purely visual layers drawn under/over the main
  collision layer) and `TileMap.tileAnimations`/`tileAnimationFps` +
  new `TileAnimationSystem` (base tile id cycles through a set of
  frames over time, resolved via `TileMap.currentTileId`) — collision
  always keys off the base id regardless of which frame is showing.
- **Swimming / water physics**: new `WaterZone` component +
  `WaterPhysicsSystem` (`engine_platformer`) — a `PlatformerController`
  entity overlapping a water zone gets `controller.inWater = true`,
  buoyancy-capped `Velocity.y`, and a repeatable upward "stroke" on
  `jumpRequested` instead of a single jump arc.
- **Boss/enemy phase framework**: new `BossPhase`/`BossPhaseSystem`
  (`engine_platformer`) ties `CinematicSystem` and `Health` together —
  watches an entity's health fraction and, the tick it crosses a
  configured threshold, emits `BossPhaseChangedEvent` (a game's cue to
  switch attack pattern) and optionally plays a one-shot cinematic beat.
- **Save-schema versioning**: `SaveGame.save`/`load` take a `version`
  and wrap the saved snapshot in a `{schemaVersion, world}` envelope;
  `load` takes an optional `migrate` callback and throws a new
  `SaveVersionException` on an unhandled version mismatch instead of
  silently loading wrong-shaped data. Pre-existing (unversioned) saves
  still load, read as version `1`.
- **Hitstun/knockback**: `damageEntity`/`dealDamageOnTouch` gained
  opt-in `knockbackSpeed` (pushes the damaged entity away from a
  `source`) and `hitstunSeconds` (freezes `PlatformerInputSystem`'s
  input handling for that entity via a new
  `PlatformerController.hitstunSeconds` + `HitstunSystem`).
- **Multi-line / wrapped `Text`**: new `maxWidth` field (`null` default
  — unbounded, single-line, unchanged from before) — `EngineView`
  passes it through to `TextPainter`'s own line-breaking, scaled by
  `Camera.zoom` in world space the same way `fontSize` already is.
- **Tile culling**: `_collectTileMapItems` now only walks tiles inside
  the current viewport (converted to tile-grid indices via
  `Camera.screenToWorld`), instead of every tile in the map every
  frame — render cost now scales with visible tiles, not total map
  size.
- **9-slice sprites**: new `NineSliceSprite` component — a resizable
  UI panel/dialog-box background from one atlas region, corners at
  native size, edges/center stretched to fill.
- **Priority-queue pathfinding**: `findPath`'s open set is now a binary
  min-heap instead of a sort-then-take-first list — O(log n) insert/
  extract-min instead of O(n log n) every iteration. Behavior-preserving.
- **Animation clip transitions**: `AnimationState.crossfadeSeconds`
  (opt-in, off by default) + new `AnimationTransition` component/
  `AnimationTransitionSystem` — a frozen-frame crossfade fades the
  outgoing clip's last frame out instead of popping instantly to the
  new clip.
- **Fixed-timestep + render interpolation**: new
  `EngineView.fixedTimestepSeconds` (opt-in, `null`/off by default) —
  decouples simulation from display refresh rate (a fixed-size
  `world.step` regardless of frame rate, capped backlog on a slow
  frame) and interpolates `Sprite`/`Particle` positions between
  simulated states for smooth motion at any display rate.
- **Localization / i18n**: new `StringTable` (`engine_core`) —
  JSON-authorable strings keyed by id then locale, with `{param}`
  substitution and a locale → default-locale → raw-key fallback chain.
- **Basic 2D lighting**: new `Light2D` component + `EngineView.ambientBrightness`
  (opt-in, `1.0`/off by default), also plumbed through
  `GameConfig.ambientBrightness` — darkens the scene and reveals it
  again through each light's soft radial falloff.
- **Lighting follow-ups** (all five, one pass): `Scene.ambientBrightness`
  per-scene override (`ButtonMenuScene` opts every menu out of
  darkening automatically); `Light2D.colorArgb` additive tint (alpha
  channel is tint strength, `0` = no tint pass at all); `Light2D.castsShadows`
  — real occlusion by `TileMap` walls via a `raycastTileMap`-sampled
  visibility polygon; `Light2D.flickerSpeed`/`flickerAmount` + new
  `LightFlickerSystem` for guttering/pulsing lights; `Light2D.coneAngle`/
  `coneDirection` for flashlight-style directional lights (composes
  with shadow casting for free — both use the same clip-path code).

This closes out the "Rendering (`engine_flutter`)" group of "New engine
features (round 2)" — see TODO.md for the remaining Core/Platformer
items in that section.

- **Lighting: viewport culling + configurable shadow ray count**:
  `EngineView` now skips a `Light2D` entirely (including its
  shadow-casting raycasts) once its screen-space circle no longer
  reaches the visible viewport, and the shadow-casting visibility
  polygon's ray count is now `Light2D.shadowRayCount` (`48` default,
  unchanged) instead of a hardcoded constant — both found from actually
  running several shadow-casting lights together in `test_game`.
- **Ladders, conveyors, per-tile friction**: `TileMap` gained
  `ladderTileIds`, `conveyorSpeedByTileId`, and `frictionByTileId`
  (all opt-in, empty by default, unchanged behavior for untagged
  tiles); new `engine_platformer` `LadderSystem` (opt-in via
  `PlatformerController.climbSpeed`) turns up/down input into vertical
  climb movement while overlapping a ladder tile;
  `PlatformerInputSystem` slides instead of snapping grounded velocity
  when standing on a low-friction (icy) tile; `TileCollisionSystem`
  nudges `Position.x` for an entity grounded on a conveyor tile. First
  item of the "Platformer (`engine_platformer`)" group of "New engine
  features (round 2)" — see TODO.md for the rest.
- **AI steering/avoidance**: new `AvoidanceBehavior`, a decorator
  around any `Behavior` (`AvoidanceBehavior(PatrolBehavior(...))`) that
  blends a horizontal separation push away from nearby `AIState`-
  carrying entities on top of the wrapped behavior's own decision,
  instead of overriding it — packs of `PatrolBehavior`/`FollowBehavior`/
  `PathFollowBehavior` entities no longer overlap/stack when their
  paths cross.
- **Ledge grab / mantle**: new `PlatformerController.ledgeGrabEnabled`
  (opt-in) + new `LedgeGrabSystem` — an airborne entity touching a
  wall right at its top edge grabs on instead of sliding/falling past
  it, freezing in place until the player mantles up (hold up/jump) or
  drops (hold down). `engine_platformer`'s `README.md` also brought up
  to date in the same pass: a new "Movement feel" section documents
  every `PlatformerController` field (several previously undocumented
  entirely), a new "Tile-based terrain features" section covers
  ladders/conveyors/friction, and the system-order/Behaviors/Damage
  sections were corrected to match the current code.

### Fully-fledged platformer engine

Working through the gap list in TODO.md's "Fully-fledged platformer
engine" section, one item at a time.

- **Moving/kinematic platforms**: `PlatformerSystem` now carries a
  resting rider along a `PlatformBody` entity's horizontal `Velocity`
  — give any platform a `Velocity` (move it with `MovementSystem`, a
  `Tween`, or your own system) and a rider standing on it moves with
  it. Vertical motion already carried a rider "for free" since the
  collision AABB is recomputed from the platform's current position
  every tick; only horizontal needed the fix.
- **Modern jump-feel primitives**: coyote time, jump buffering, double
  jump, wall jump, wall slide, and dash — all opt-in per
  `PlatformerController` field (every default keeps the original
  strict grounded-jump behavior). New `DashSystem`. `collision_math.dart`'s
  `resolveSolidCircleAabb` now returns a `CollisionSide` enum instead
  of a bool, so wall contact can be derived from the same collision
  call that already resolved "grounded."
- **Sloped tile collision**: `TileMap.slopeUpRightTileIds`/
  `slopeUpLeftTileIds` + `TileCollisionSystem` — a walkable ramp
  surface (floor height linearly interpolated across the tile), not
  full polygon physics.
- **Tiled `.tmx` import**: `tileMapFromTmx` parses a self-contained
  (embedded tileset, CSV layer data) `.tmx` into a `TileMap`, with
  per-tile bool properties (`solid`/`oneWay`/`slopeUpRight`/
  `slopeUpLeft`) mapping onto the matching collision set.
- **`game_agent lint --render`**: rasterizes a level's `TileMap` (color-
  coded by collision kind) plus a labeled marker per named entity to a
  PNG, so a level's shape is visible without running the game.
- **`TriggerZone`** + `installTriggerZones`: a general "fires
  `TriggerEvent` on touch, never blocks movement" primitive — the
  generic counterpart to `RoomExit`. Along the way, fixed
  `EventBus.flush()` to deliver events emitted by another event's
  handler within the same flush, instead of a tick later.
- **`Pushable`** + `PushableSystem`: genre-general entity-pushes-entity
  resolution (a crate, a boulder) — pairs with `PlatformerController`
  for wall-blocking rather than duplicating tile/platform collision.
- **Ranged/projectile combat**: `Projectile` + `spawnProjectile` +
  `ProjectileSystem` (lifetime expiry) + `installProjectileDamage`
  (on-hit damage via one shared subscription, not one per projectile).
- **Remappable controls**: `InputController.captureNextKeyDown` (raw
  next-key capture) + `InputBindingsStorage` (save/load bindings) +
  `RemapMenuScene` (a ready-made "press a key to rebind" menu).
- **Screen shake**: `Camera.shake`/`Camera.update`, a decaying random
  jitter offset baked into `worldToScreen`/`screenToWorld` — `EngineView`
  now calls `camera.update(dt)` every frame unconditionally (`Camera`
  previously had no per-tick lifecycle hook at all).

This closes out every item added under "Fully-fledged platformer
engine" above.

### New engine features

Working through TODO.md's "New engine features" section, one item at
a time.

- **Text rendering**: `Text` component (`engine_flutter`) — drawn
  fresh every frame via `TextPainter`, `screenSpace` chooses
  world-space (scrolls/zooms with the camera) vs. screen-space (fixed
  viewport pixels, for a HUD).
- **Debug visualization**: `EngineView.showColliderDebug`/
  `GameConfig.showColliderDebug` — a stroked outline per `Collider` and
  per solid/one-way/slope `TileMap` tile. Also fixed slope tiles
  rendering visually identical to solid tiles in the normal renderer.
- **Raycasting**: `raycastTileMap` (grid-DDA, no tunneling through thin
  walls) + `raycastEntities` (nearest ray-vs-circle hit).
- **AI depth**: `findPath` (`engine_core`) — 4-directional A* pathfind
  over a `TileMap`. `WorldView.hasLineOfSight`, built on
  `raycastTileMap`. `FollowBehavior.requireLineOfSight` (opt-in, off by
  default) stops a chase blocked by a wall instead of following through
  it. New `PathFollowBehavior` (`engine_platformer`) walks a `findPath`
  route one waypoint at a time.
- **HUD/UI framework**: `HudBar` component (`engine_flutter`) — a
  screen-space filled-rect bar (health/stamina/boss meters). New
  `HealthHudLink`/`HealthHudSystem`/`spawnHealthHudBar`
  (`engine_platformer`) wire a `HudBar` to an entity's `Health`,
  kept in sync every tick.
- **`lib/src/` restructured by concern** in all three packages
  (`ecs`/`physics`/`ai`/`rendering`/`ui`/`content` in `engine_core`;
  `rendering`/`audio`/`input`/`logic`/`ui` in `engine_flutter`;
  `physics`/`ai`/`logic`/`rendering`/`ui` in `engine_platformer`)
  instead of the flat `components/`/`systems/` split. Pure file moves
  plus import-path fixups, zero behavior change — every public export
  path is unchanged, only its internal `src/...` target moved.

This closes out every item added under "New engine features" above.

## [0.1.0]

### Scenes, menus & rooms

- **Room/door transitions**: `RoomExit` component (`engine_core`) +
  `installRoomExitTrigger` (`engine_flutter`) — touch a door, load the
  target `Scene`, appear at the matching spawn marker. The target scene
  is referenced by id (resolved against a game-registered factory map),
  the same "data references registered code" pattern as
  `AIState.behaviorId`.
- **`GameState`**: a JSON-serializable data bag that survives a
  `SceneController.loadScene` switch, unlike `World` (which is rebuilt
  from scratch per scene on purpose). A game reads/writes it across
  rooms/menus for things like a running score or unlocked content.
- **`Scene` / `SceneController`**: `engine_flutter`'s scene-management
  layer — `loadScene` (tear down and load a new room),
  `pushOverlay`/`popOverlay` (freeze the current scene under a menu
  without losing its state, e.g. a pause menu), and
  `Scene.showOnScreenControls` so a tap-driven menu doesn't show a
  joystick/action buttons meant for gameplay.
- **`ButtonMenuScene`** + `MenuButtonSpec`: a ready-made ECS menu —
  give it a button list and an action handler, it spawns the button
  entities and hit-tests taps against them. Built on a new generic
  `Button` component + `hitTestButton` in `engine_core`.
- **Human-authorable levels**: `TileMap.fromJson` accepts a
  `legend` + ASCII `rows` shape (characters instead of a flat id
  array) alongside the original flat-array form; `Level.loadInto` can
  name entities (`"name"` key) and returns a name → `EntityId` map, so
  a scene can look up "the player"/"a door" after a data-driven level
  load.
- **`SaveSlotMenuScene`** + `SaveSlotSpec`: a ready-made save/load
  slot-picker menu on top of `SaveGame` — checks `hasSave` per slot on
  every `populate` and reflects that in each button's label.
- **Cinematic support**: `CinematicSystem` + `CinematicStep`
  (`WaitStep`/`CallbackStep`/`TweenStep`) in `engine_core` — plays a
  scripted, non-interactive sequence (a cutscene, a boss intro) as a
  normal `System`, built on `Tween`'s own easing math. `skip()` jumps
  straight to `CinematicCompleteEvent`.

### Platformer & gameplay helpers (`engine_platformer`)

- Damage/health/combat and checkpoint/respawn helpers
  (`damageEntity`/`healEntity`, `Checkpoint`/`LastCheckpoint`,
  `respawnPlayer`).
- Collectible/inventory helpers (`Inventory`, `collectItem`,
  `dealPickupOnTouch`).
- Patrol/follow AI behaviors, facing + movement-driven animation,
  `installPlatformerSystems` (registers every platformer system in the
  one order that's actually correct).
- Shared `spawnPlayer`/`spawnEnemy` spawn logic; shared
  `collision_math.dart` between `PlatformerSystem` and
  `TileCollisionSystem`.

### Rendering & assets (`engine_flutter`)

- z-index draw ordering for `Sprite`/`ParallaxLayer`/`TileMap`/
  `Particle`, with `Canvas.drawAtlas` batching per shared atlas/z-slot
  for sprite-heavy scenes.
- Particle effects (data + system in `engine_core`, rendering in
  `engine_flutter`) and parallax scrolling backgrounds.
- Tweening/easing helpers (`Tween`/`EasingType`/`TweenSystem`).
- Real sprite asset loading (`SpriteAtlas.loadFromAssets`) and audio
  playback (`AudioManager`, via `audioplayers`).
- `SaveGame`: cross-platform `World` snapshot save/load.
- A fuller `EngineView` debug overlay (fps, tick, entity/sprite/
  particle counts, resident memory where available).

### Input

- Mobile input: on-screen virtual joystick + buttons
  (`OnScreenControls`, `GameConfig.onScreenControls`), with haptics,
  press-scale animation, analog joystick output, sprite-customizable
  buttons, and a floating (not fixed-position) joystick to avoid
  overlapping gameplay content or the camera.

### Engine core & performance

- Spatial-hash collision (`CollisionSystem`) with an auto-sized cell
  size, and typed direct dispatch in `EventBus` (replacing
  `Function.apply`).
- `ComponentStore`'s sparse side switched from `Map<int,int>` to a
  `List<int>`. Along the way, fixed a real bug found by the benchmark
  suite: `remove` left a dangling sparse-index entry when removing the
  last entity in a store, which could silently corrupt component data
  or crash once a recycled entity id collided with it under sustained
  spawn/destroy churn.
- A performance benchmark suite (`benchmark/` in `engine_core`/
  `engine_platformer`) and a full pass to 100% test coverage across
  `engine_core`/`engine_flutter`/`engine_platformer`.

### Tooling

- `engine_cli`'s `game_agent` CLI: `create` (scaffold a new game),
  `upgrade` (repin an existing game's engine version), `lint` (validate
  a level/content file without running the game).
- `create`'s generated starter project rewritten to a real
  `engine_platformer` starting point (a small data-driven tile level +
  player, `installPlatformerSystems`) instead of the original
  bouncing-circle stress-test demo. `upgrade` now rewrites every
  self-referencing engine package's git ref in a project's
  pubspec.yaml, not just `engine_core`'s.

### Foundation

- Initial ECS scaffold (`engine_core`): `World`, `ComponentStore`,
  systems, spatial hash.
- `engine_flutter`: the Flutter shell — sprites, animation, camera,
  input, `EngineView`.
- `engine_platformer` split out from `engine_core` so a non-platformer
  2D game isn't forced to depend on gravity/jump concepts.
- The content DSL (`Level`) and the agent-facing runtime API
  (`WorldView`/`Behavior`/`AISystem`) — world state as data an agent
  can read/patch, and a sandboxed way for an agent to drive an entity
  without a path to corrupting simulation state.
- Tile-based platformer physics: gravity, ground detection, jump,
  one-way platforms; `TileMap` + `TileCollisionSystem`.
- `GameConfig` + the `Game`/`runGame` app framework.
