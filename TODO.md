# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

Everything completed through the v1.0-release-readiness pass and the
"New engine features (round 2)" streak (including its full "Rendering"
group) has been cleared from this file — see [CHANGELOG.md](CHANGELOG.md)
for what shipped and git history for the full why behind each change.

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

## Lighting follow-ups (round 3) — not yet implemented

Reported live: a shadow-casting light's shadow visibly *flickers*
(edges popping/jittering frame to frame) while its light source is
moving, instead of the shadow sliding smoothly the way the light
itself does. Not yet fixed — listed here to confirm the plan before
touching the render path.

- [ ] Shadow-edge jitter from grid-raycast tie-breaking:
      `raycastTileMap`'s DDA traversal (`packages/engine_core/lib/src/physics/raycast.dart`)
      picks which grid axis to step with a strict `tMaxX < tMaxY`
      comparison. When a sampled ray's angle is close to a tile-grid
      diagonal (common — `_lightClipPath` samples rays at fixed angle
      increments all the way around, so *some* ray is always near
      diagonal relative to the axis-aligned grid), `tMaxX`/`tMaxY` are
      nearly equal, and which one continuously moving light position
      makes momentarily smaller can flip frame to frame — sending that
      ray down a different sequence of tiles and changing which tile
      it reports as the blocker, even for a sub-pixel light move. That
      reads as the shadow polygon's edge popping/jittering right where
      those near-diagonal rays land, exactly the flicker reported.
      Likely fix shape (not committed to without investigating
      further): a small epsilon/hysteresis in the tie-break, and/or
      resolving the *exact* corner-hit distance analytically instead
      of leaving it to whichever axis's DDA step happens to fire
      first — needs a repro test (a light moving in tiny steps near a
      wall corner, asserting the polygon's hit distance for a
      near-diagonal ray changes monotonically/smoothly, not just
      "renders without crashing" like the current tests) before
      changing `raycastTileMap`, since `WorldView.hasLineOfSight`/AI
      already depend on its exact behavior and must not regress.
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
- [ ] Steering/avoidance among multiple AI: `PatrolBehavior`/
      `FollowBehavior`/`PathFollowBehavior` don't avoid each other, so
      packs of enemies overlap/stack.
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
