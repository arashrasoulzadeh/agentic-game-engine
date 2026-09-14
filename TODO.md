# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

Everything completed through the v1.0-release-readiness pass and the
"New engine features (round 2)" streak (including its full "Rendering"
group) has been cleared from this file — see [CHANGELOG.md](CHANGELOG.md)
for what shipped and git history for the full why behind each change.

## Documentation

- [ ] `engine_flutter`'s `README.md` doesn't document `Light2D`/
      `EngineView.ambientBrightness` (basic 2D lighting, including
      shadow casting/flicker/cone lights/viewport culling), `NineSliceSprite`,
      `AnimationTransition`/crossfading, `EngineView.fixedTimestepSeconds`,
      or `StringTable` at all — all shipped this project's "New engine
      features (round 2)" streak with full code-level doc comments and
      tests, but never made it into the package README's own feature
      tour. `engine_platformer`'s README was brought up to date in the
      same pass that added ledge grab (movement-feel fields, ladder/
      conveyor/friction tiles, `AvoidanceBehavior`,
      `PathFollowBehavior`, full system order, `damageEntity`'s
      knockback/hitstun params) — `engine_flutter` and `engine_core`
      need the equivalent pass. `engine_core`'s README should be
      checked too (`entitiesWithAll`/`entitiesWithinRadius`,
      `SaveGame` schema versioning, the `_MinHeap`-based pathfinding
      rewrite, `StringTable`) — spot-checked lighter than
      `engine_flutter`'s gap but not confirmed complete.

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

- [x] Textured `TileMap` rendering: new `TileMap.atlasId` (`null`
      default) + `TileMap.regionByTileId` (empty default — a tile id
      with no entry still falls back to the flat debug color even when
      `atlasId` is set, so a level can texture some ids and leave
      others, e.g. an invisible trigger marker, as plain color).
      `EngineView._collectTileMapItems` resolves the atlas once per
      `TileMap` (not per tile) and, for each tile id with a real,
      loaded region, `canvas.drawImageRect`s it instead of the flat
      color — the exact same region-in-an-atlas mechanism `Sprite`
      already uses, just applied per grid cell. Kept as plain
      `String`/`Map<int, String>` fields on `TileMap` (`engine_core`,
      no Flutter dependency) rather than anything Flutter-typed, same
      pattern `Sprite.atlasId`/`.region` already establish in
      `engine_flutter`; `TileMap` already carried one rendering hint
      (`zIndex`) so this isn't a new kind of leak. Verified: 2 new
      `engine_core` tests (round-trip, and `atlasId` omitted from
      `toJson` entirely — not serialized as `null` — when unset) and 3
      new `engine_flutter` widget tests (a tile with a real loaded
      region draws without error; a tile id with no `regionByTileId`
      entry falls back to flat color even when `atlasId` is set and
      loaded; an `atlasId` that isn't registered yet in the
      `AtlasRegistry` falls back cleanly, not a crash). Full
      `engine_core` (176), `engine_flutter` (198), and
      `engine_platformer` (176) suites green, `--fatal-infos` analyze
      clean on all three. Live in `test_game`: `main.level.json`'s
      ground/platform tiles (`solidTileIds: {1}`) now reference the
      `tileset` atlas's existing `dirt_top_mid` region (an atlas the
      game already loaded but never used for anything) — the level
      visibly renders real dirt texture instead of flat gray blocks,
      while the ladder/icy/conveyor tiles keep their distinct
      translucent colors (no `regionByTileId` entry for those ids).

## New engine features (round 2) — Core (`engine_core`)

- [ ] Multi-layer / animated tiles: `TileMap` is single-layer with no
      per-tile animation (torches, water) — most real levels want at
      least a background/foreground layer split.
- [ ] Deterministic RNG + replay/record: no seeded RNG helper and no
      input-replay capture exist yet, both of which matter for
      reproducible testing/debugging of an agent-driven or
      physics-heavy game.
- [ ] Content hot-reload: no way to re-load a level/`GameConfig` JSON
      file into a running `World` without a full app restart — this
      engine markets itself as agent-friendly/iteration-friendly, and
      fast content-edit-see-result loops are a big part of that promise
      that isn't delivered yet.

## Lighting follow-ups

Real gaps identified while building and then actually using basic 2D
lighting (`Light2D`/`EngineView.ambientBrightness`) in `test_game` —
all five closed out in one pass.

- [x] Per-scene ambient brightness: new `Scene.ambientBrightness`
      (`null` default — "use `GameConfig`'s global setting," unchanged
      behavior) that `Game` prefers over the global config value when
      set (`loaded.scene.ambientBrightness ?? widget.game.config.ambientBrightness`).
      `ButtonMenuScene` (the base every menu in this engine builds on,
      not just one specific menu) overrides it to `1.0` — a menu isn't
      a lit game world and shouldn't darken just because gameplay uses
      lighting. Verified live in the browser: `test_game`'s main menu
      no longer darkens (confirmed both before this fix, darkened, and
      after, not).
- [x] Colored lights: `Light2D.colorArgb` (default `0x00FFFFFF` —
      *transparent* white, meaning "no tint pass at all," not opaque
      white, so the default costs nothing extra and changes nothing
      visually). The color's own alpha channel doubles as tint
      strength — an opaque-ish color like `0xAAFF6600` tints visibly,
      alpha `0` skips the whole additive pass. Implemented as a
      separate additive (`BlendMode.plus`) radial-gradient pass drawn
      *after* the darkness mask is composited back onto the real scene
      (additive blending needs the scene's actual colors underneath it,
      which only exist post-composite) — the brightness-reveal pass
      alone (via `BlendMode.dstOut`, erasing only alpha) can't add
      color, only reveal what's already there.
- [x] Shadow casting: new `Light2D.castsShadows` (`false` default,
      unchanged plain-circle behavior). When on, `EngineView` samples
      48 rays around the light via `raycastTileMap` (the exact same
      primitive `WorldView.hasLineOfSight`/AI already use) to build a
      visibility-polygon `Path`, clipping the reveal (and, if present,
      the color-tint) to it — real occlusion by `TileMap` walls, not a
      full shadow-volume renderer (a meaningfully bigger scope), but a
      legitimate, well-known 2D-shadow-casting technique. Verified two
      ways: (1) exact numeric assertions in `light2d_test.dart`'s new
      "Shadow casting occlusion math" group — a solid tile stops a
      raycast well short of the light's radius at the precise expected
      distance, an unobstructed direction reaches the full radius
      unblocked, both directly against `raycastTileMap` (the same
      primitive the render path calls), not just "doesn't crash"; (2)
      live in the browser against `test_game`'s **real level
      TileMap/textures** — the player's light, both torches, and a new
      flashlight-style cone light all have `castsShadows: true` active
      simultaneously against the actual level geometry and sprites,
      confirmed rendering with no crashes and no console errors.
- [x] Animated/flickering lights: `Light2D` gained `flickerSpeed` (`0`
      default — disabled) + `flickerAmount`, `baseIntensity`/
      `baseRadius` (defaulted from the constructor's `intensity`/
      `radius` args so enabling flicker on an existing light needs no
      extra setup), and `flickerElapsed` (runtime). New
      `LightFlickerSystem` oscillates `intensity`/`radius` around the
      base values using two layered sine waves (deliberately not real
      randomness — smoother frame-to-frame, and keeps `Light2D` plain
      seedless data rather than needing a stored, JSON-round-trip-safe
      `Random` seed per light) — a no-op, near-zero-cost for any light
      with `flickerSpeed == 0`. Verified: `LightFlickerSystem` tests
      confirm disabled-by-default is a true no-op, oscillation stays
      correctly bounded, and intensity clamps to `[0, 1]` even under a
      deliberately extreme `flickerAmount`. Live in the browser:
      `test_game`'s two torches flicker (`flickerSpeed: 3,
      flickerAmount: 0.15`) with no crashes.
- [x] Directional/cone lights: `Light2D.coneAngle` (`null` default —
      full 360° point light, unchanged) + `coneDirection`. When set,
      the same visibility-polygon machinery shadow casting uses builds
      a pie-slice fan instead of a full circle (sampling only across
      the cone's angular width) — cones and shadow casting compose for
      free, since both go through the identical clip-path code path.
      Verified: dedicated cone and shadow-casting-cone widget tests
      render without crashing; live in the browser, `test_game`'s new
      flashlight-style cone light (`coneAngle: 0.9`, also
      shadow-casting) renders correctly against the real level.

All five verified together, live, in one pass: `test_game`'s player
light, two colored/flickering torches, and the new cone light are all
active simultaneously against the level's real `TileMap`/sprite
textures, with `showColliderDebug`/the FPS overlay/coin HUD text all
still rendering correctly on top. Full `engine_flutter` suite green
(15 new tests in `light2d_test.dart`, bringing it to 22, plus 1 new in
`button_menu_scene_test.dart`), `dart analyze --fatal-infos` clean.

## Lighting follow-ups (round 2)

Two more gaps, spotted after actually running several shadow-casting
lights together in `test_game`: every `Light2D` in the world was
processed every frame regardless of whether it was anywhere near the
camera, and shadow raycasting always sampled a hardcoded 48 rays no
matter how small or large the light. Both closed out in one pass.

- [x] Viewport culling: `EngineView._drawLighting` now skips a light
      entirely — including its shadow-casting raycasts, the expensive
      part — when its screen-space circle doesn't intersect the
      current viewport rect (`_circleIntersectsRect`, a closest-point-
      on-rect distance check). Purely an internal cost cut, no API
      change and no visible behavior change for anything on screen;
      matches the same reasoning as `_collectTileMapItems`'s earlier
      tile culling. Verified: a dedicated widget test places a
      shadow-casting light thousands of pixels outside a 400×300
      viewport and confirms it still renders without crashing (proving
      the cull path itself, not just "renders," since a bug in the
      cull math throwing or producing a degenerate rect would show up
      here); the existing on-screen shadow-casting tests continue to
      pass unchanged, confirming lights actually on screen are
      unaffected.
- [x] Configurable shadow ray count: new `Light2D.shadowRayCount`
      (`48` default — the feature's original fixed value, unchanged
      behavior for any light that doesn't set it), read by
      `EngineView._lightClipPath` instead of the hardcoded constant,
      clamped to a minimum of `3` (fewer rays can't describe a closed
      polygon). Lets a level with many small shadow-casting lights on
      screen at once cut the per-light raycast cost, or one big
      dramatic light raise it past 48 to smooth out visibly faceted
      polygon edges — a real tuning knob discovered from having four
      shadow-casting lights active simultaneously in `test_game`.
      Verified: round-trip test in `light2d_test.dart`, plus widget
      tests for a custom count and for a count below the `3` floor
      (confirms the clamp, not just "doesn't crash on a weird input").
      Live in `test_game`: the player's light now sets
      `shadowRayCount: 64` (its widest, most prominent shadow, where
      the extra smoothness is actually visible) as a real usage
      example.

Full `engine_flutter` suite green (194 tests, 5 new in
`light2d_test.dart`), `dart analyze --fatal-infos` clean.

## Lighting follow-ups (round 3)

Reported live: a shadow-casting light's shadow visibly *flickers*
(edges popping/jittering frame to frame) while its light source is
moving, instead of the shadow sliding smoothly the way the light
itself does — fixed (see below). Also reported: lighting quality in
general "not very good" — two visual-quality items closed out
alongside the flicker fix and `blockOneWayPlatforms`, described below.
Remaining open items (entity shadow casting, additive overlap,
fixed-timestep interpolation) still need a design pass before
implementing.

- [x] Shadow-edge jitter from grid-raycast tie-breaking:
      `raycastTileMap`'s DDA traversal now steps *both* grid axes
      together whenever `tMaxX`/`tMaxY` are within a small epsilon
      (`1e-6`) of each other, instead of picking one via a strict `<`
      comparison. A ray passing near a tile-grid corner (common —
      `_lightClipPath` samples rays all the way around a light, so
      *some* ray is always near-diagonal relative to the axis-aligned
      grid) used to have `tMaxX`/`tMaxY` nearly tied, and which one a
      continuously moving light's position made momentarily smaller
      could flip from one frame to the next — sending the ray down a
      different sequence of tiles and changing whether a corner-
      adjacent solid tile blocked it, for a sub-pixel light move. That
      read as the shadow polygon's edge popping right where those
      near-diagonal rays landed. Stepping both axes together at a near-
      tie treats the ray as passing exactly through the shared corner
      (skipping straight to the diagonal tile, the same convention
      most grid-DDA-with-diagonal-handling implementations use) —
      deterministic regardless of which side of the tie a tiny origin
      perturbation falls on, so the flicker is gone at its actual
      source rather than papered over with smoothing. This is a real,
      if narrow, behavior change for the previously-undefined exact-
      corner case (a corner-adjacent solid tile that used to
      block a ray passing exactly through the corner no longer does,
      consistently) — `WorldView.hasLineOfSight`/pathfinding/AI all
      share this same primitive and their full test suites stayed
      green, so nothing else depends on the old tie-break's specific
      direction. Verified: new regression test in
      `engine_core`'s `raycast_test.dart` — five origins perturbed by
      sub-pixel amounts (`0`, `±1e-7`, `3e-8`, `-5e-8`) around an exact
      corner-tie all now produce the identical raycast result (all
      miss, consistently) where they'd previously have diverged
      (some hitting the corner-adjacent solid tile, some not) based on
      floating-point noise alone. Full `engine_core` (176),
      `engine_flutter` (198), and `engine_platformer` (176) suites
      green, `--fatal-infos` analyze clean on all three.
- [ ] Shadow/light position isn't run through `EngineView`'s
      fixed-timestep interpolation: `_drawLighting` reads a light's
      `Position` directly from the component store, while `Sprite`/
      `Particle` rendering goes through `_interpolated` (blends toward
      the current tick using `interpolationAlpha`) whenever
      `fixedTimestepSeconds` is set (see this session's earlier fixed-
      timestep work). A light attached to a moving entity (e.g. the
      player, as `test_game` does) would visibly lag/step relative to
      that entity's own smoothly-interpolated sprite instead of
      tracking it exactly — `test_game` doesn't currently set
      `fixedTimestepSeconds` so this isn't the cause of the flicker
      just reported, but it's a real latent gap for any game that
      does turn fixed-timestep on. Fix shape: thread `_interpolated`
      through `_drawLighting`'s `worldPos` lookup the same way the
      sprite/particle passes already do.
- [x] One-way platforms never block light/shadows: new opt-in
      `Light2D.blockOneWayPlatforms` (`false` default, matching
      `raycastTileMap`'s own default and today's unchanged behavior)
      threaded straight into `_raycastLightDistance`'s `raycastTileMap`
      call. Verified: new test in `light2d_test.dart`'s "Shadow
      casting occlusion math" group asserts a one-way tile blocks a
      raycast when `blockOneWay: true` but not at the default, at the
      exact primitive `_raycastLightDistance` uses; a new widget test
      exercises a shadow-casting light with `blockOneWayPlatforms:
      true` against a real one-way `TileMap` tile end to end (renders
      without crashing). Live in `test_game`: the player's light now
      sets `blockOneWayPlatforms: true` (it's the one light actually
      near the level's one-way platforms) — loads and plays normally,
      steady 120fps, no console errors.
- [ ] Only `TileMap` geometry casts shadows — a `castsShadows` light's
      visibility polygon is built purely from `raycastTileMap`, which
      only ever tests tile grid cells. Nothing with a `Collider` (a
      crate, a pillar, a closed door, any prop or dynamic obstacle
      that isn't baked into the tile grid) blocks light at all — stand
      a solid-looking prop directly between a torch and a wall and the
      torch's light (and any shadow polygon) passes straight through
      it as if it weren't there. Real gap for any level that places
      solid *entities* rather than only tile geometry between a light
      and what it's lighting. Fix shape: a per-ray nearest-hit check
      against `Collider`s tagged as light-blocking (a new opt-in flag,
      not every `Collider` — most colliders, like a coin or an enemy's
      hurtbox, shouldn't cast a shadow), merged with the existing
      tile-hit distance the same way multiple `TileMap`s already are
      in `_raycastLightDistance`.
- [ ] Overlapping lights don't add brightness: the reveal pass punches
      holes in the darkness mask via `BlendMode.dstOut`, which only
      ever *erases* alpha — a second light's circle overlapping a
      first's can't push the shared region any brighter than whichever
      single light's `intensity` erases the most, since alpha has
      nowhere to go below `0`. Real light is additive: two torches
      standing close together should visibly brighten the ground
      between them beyond what either manages alone, and right now
      that area looks identical to just the stronger of the two. Not
      simply a matter of switching blend modes — reveal (dstOut,
      operating on the darkness mask's alpha) and tint (`BlendMode.plus`,
      operating on real scene color) are different passes for a
      reason (see `_drawLighting`'s doc comment on ordering), so this
      needs its own design pass, not a one-line blend-mode swap —
      logged here rather than attempted inline.
- [x] Softer, more natural falloff + soft shadow edges: the reveal/tint
      radial gradients went from a flat 2-stop linear falloff (uniform
      dimming center-to-edge, which read as artificial) to a 3-stop
      shape — full intensity out to 0, `intensity * 0.55` at 55% of the
      radius, transparent at the edge — a brighter, more defined core
      with a gentler tail, shared between both passes via one constant
      stop list so they stay visually consistent. Separately, a
      shadow-casting/cone light's visibility polygon (a `shadowRayCount`
      -sided approximation of a curve, so its edges are visibly
      faceted/straight) now gets a small `MaskFilter.blur` on its
      reveal and tint paints, applied once per light per frame — not
      per sampled ray, so it doesn't scale with `shadowRayCount` the
      way the raycasting itself does — softening the polygon boundary
      into a gradient instead of a hard, jagged cutoff. `null` (no
      blur) for a plain circular light, which has no polygon edge to
      soften in the first place. Both changes are pure rendering-paint
      tweaks — no new raycasts, no per-tile cost, same asymptotic cost
      as before. Verified live in `test_game`: steady 120fps before and
      after, no console errors; full `engine_flutter` suite (201
      tests, all pre-existing "renders without crashing" lighting
      tests still pass unchanged) confirms nothing broke.

## New engine features (round 2) — Platformer (`engine_platformer`)

- [x] Ladders/climbing, conveyors, per-tile friction: `TileMap` gained
      `ladderTileIds` (plain overlap marker, `engine_core`, same
      genre-general-data reasoning as every other `*TileIds` set),
      `conveyorSpeedByTileId` (px/s nudge to `Position.x` while resolved
      grounded on that tile id), and `frictionByTileId` (multiplier on
      how fast grounded velocity snaps to the input target — missing
      entry, the default, means `1.0`/instant-snap, unchanged). New
      `engine_platformer` `LadderSystem` (opt-in via
      `PlatformerController.climbSpeed`, `0` default disables it, same
      convention as `wallJumpPushSpeed`) reads `onLadder` (set by
      `TileCollisionSystem`, reset by `PlatformerSystem` alongside
      `grounded`) and up/down input to override `Velocity.y`, run last
      in `installPlatformerSystems` so it has final say over gravity/
      jump that tick. `PlatformerInputSystem` blends toward the input
      target instead of snapping when `groundFriction < 1.0` (icy
      tiles slide); `TileCollisionSystem` applies conveyor/friction only
      on the tile actually landed on this tick, alongside the existing
      solid/one-way/slope branches. All additive/opt-in — a level with
      no tagged tiles behaves exactly as before (proven by the full
      pre-existing suite passing unchanged). Verified: new tests in
      `engine_core`'s `tile_map_test.dart` (round-trip + defaults) and
      `engine_platformer`'s `tile_collision_test.dart` (ladder overlap
      set/reset, conveyor nudges `Position.x` while grounded, friction
      sets/defaults `groundFriction`) and new `ladder_friction_test.dart`
      (friction blending vs. snap, grounded-only, `LadderSystem`'s
      climb/hold/no-op/not-on-ladder behavior) — `flutter test`/
      `dart test` and `--fatal-infos` analyze clean across all three
      packages. Live in `test_game`: added a small ladder column, an
      icy ground patch, and a conveyor ground patch to
      `main.level.json` near the spawn — the level loads and renders
      correctly with the new tile ids/legend entries (no crash, no
      console error), confirming `TileMap.fromJson`'s new fields
      round-trip through the human-authorable legend form correctly;
      actually walking onto them to see the climb/slide/push in motion
      hit the same simulated-keyboard-hold limitation noted earlier in
      this project's session history (arrow-key presses via the browser
      tool don't reliably sustain held movement) — not attempted to
      fake, the physics itself is covered by the unit tests above
      instead.
- [x] Steering/avoidance among multiple AI: new `AvoidanceBehavior`, a
      decorator around any existing `Behavior`
      (`AvoidanceBehavior(PatrolBehavior(...))`) that blends in a
      horizontal separation push away from nearby `AIState`-carrying
      entities (not literally everything within range — the player, a
      coin, a projectile are left alone) on top of whatever the wrapped
      behavior decides, rather than overriding it outright. A decorator
      rather than logic added to each of `PatrolBehavior`/
      `FollowBehavior`/`PathFollowBehavior` individually, since all
      three would otherwise need the identical nearby-entity scan and
      push-apart math duplicated three times. Uses
      `WorldView.entitiesWithinRadius` (added earlier this round).
      Verified: new `avoidance_behavior_test.dart` — two overlapping
      patrol entities end up with different velocities (one pushed
      back, one pushed further forward) rather than the identical
      velocity `PatrolBehavior` alone would give both; a nearby
      `AIState`-less entity (standing in for the player) causes no
      push at all; no push beyond `avoidRadius`; delegates cleanly when
      the wrapped behavior itself has nothing to do. Full
      `engine_platformer` suite (167 tests) green, `--fatal-infos`
      analyze clean. Wired into both of `test_game`'s existing
      patrollers (`AvoidanceBehavior(PatrolBehavior(...))`) — harmless
      as shipped, since their patrol bands don't currently overlap
      (different platform tiers), but exercised directly: a temporary
      third patroller spawned on top of the first (same band, same
      behavior) loaded and ran with no crash/console error, confirming
      the wiring itself (`spawnEnemy` + `AvoidanceBehavior` +
      `AISystem`) works end to end in a real scene; watching the
      actual separation happen live hit the same simulated-input
      limitation noted elsewhere in this file, so the precise push-
      apart math is what the unit tests above assert directly instead.
- [x] Ledge grab / mantle: new `PlatformerController.ledgeGrabEnabled`
      (`false` default, opt-in) + new `LedgeGrabSystem`. Detection is a
      tile-grid approximation in the same spirit as
      `resolveSlopeCircleAabb`'s "walkable surface, not true polygon
      physics": while airborne and touching a wall
      (`touchingWallLeft`/`touchingWallRight`, already resolved by
      `PlatformerSystem`/`TileCollisionSystem`), the tile beside the
      entity in the wall's direction must be solid at the entity's own
      row (the wall being touched), the tile one row above that must be
      empty (open headroom — this is what makes it specifically the
      wall's *top edge*, not an arbitrary point up a tall wall), and
      the tile directly above the entity's own row must be empty too
      (room for the entity's own head once it climbs up). On grab,
      `Velocity` freezes to `(0, 0)` every tick (overriding gravity/
      input — no sideways movement while hanging) until the player
      mantles (hold up/jump — teleports to a target position/one tile
      up, half a tile forward, precomputed once at grab time from the
      tile geometry that triggered it) or drops (hold down, releasing
      the grab and letting gravity resume). Runs after `JumpSystem`/
      `LadderSystem` so a jump input that also satisfies the grab
      condition results in a grab, not a jump — grabbing always takes
      priority. A knockback hit (`hitstunSeconds > 0`) releases an
      active grab outright rather than leaving the entity frozen
      mid-air while being knocked back. Verified: 10 new tests in
      `ledge_grab_system_test.dart` — grabs and freezes velocity at the
      correct snapped position; does *not* grab while grounded, without
      headroom above the wall (a tall solid face is not an edge),
      or without headroom above the entity itself; mantles correctly on
      both `up` and `jump` input, teleporting to the precomputed target
      and standing grounded; drops on `down` input without
      repositioning or touching velocity; keeps freezing velocity every
      tick while just hanging; and releases the grab on hitstun without
      re-freezing the resulting knockback velocity.
      `ledgeGrabEnabled: false` (the default) is a confirmed no-op even
      at an otherwise-grabbable position. Full `engine_platformer`
      suite (177 tests) green, `--fatal-infos` analyze clean. Also
      brought the package `README.md` up to date in the same pass — a
      new "Movement feel" section documents every
      `PlatformerController` opt-in field (several of which, like
      `coyoteTimeSeconds`/`wallJumpPushSpeed`/`jumpCutMultiplier`/
      `climbSpeed`, had never been documented in the README at all
      despite shipping in earlier rounds), a new "Tile-based terrain
      features" section covers ladders/conveyors/friction, the
      Behaviors section now lists `PathFollowBehavior`/
      `AvoidanceBehavior`, the system-order code block now matches
      `system_pack.dart` exactly (it was missing `DashSystem`,
      `LadderSystem`, `HitstunSystem`, `HealthHudSystem`,
      `ProjectileSystem`, and `AnimationTransitionSystem` — five
      previously undocumented systems), and the Damage/health/combat
      section now documents `damageEntity`/`dealDamageOnTouch`'s
      `knockbackSpeed`/`hitstunSeconds`/`source` parameters.
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
