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
not started, listed roughly in the order a real game would hit them.

- [ ] Per-scene (or per-`Light2D`-presence) ambient brightness instead
      of one global `GameConfig` setting — found live in the browser:
      `test_game`'s main menu darkened along with gameplay, even though
      only the gameplay scene has any `Light2D` to reveal it, since
      `ambientBrightness` has no concept of "which scene this applies
      to." A menu/HUD-only scene shouldn't go dark just because the
      game as a whole uses lighting.
- [ ] Colored lights: `Light2D` only ever reveals the scene's true
      colors (brightness/falloff only) — no way to tint what a light
      reveals (a red emergency light, a blue moonlit patch), which
      needs an actual additive-color layer, not just the darkness-mask
      punch-through this pass uses.
- [ ] Shadow casting: a `Light2D` shines straight through solid
      `TileMap`/`Collider` geometry today — no occlusion at all, so a
      light on one side of a wall still reveals the other side. Would
      need real geometry-aware shadow volumes (or a cheaper approximation
      like raycasting `raycastTileMap` per light per frame), a
      meaningfully bigger scope than the brightness-only pass that
      shipped.
- [ ] Animated/flickering lights: no built-in way to vary `Light2D.intensity`
      or `radius` over time (a guttering torch, a pulsing warning
      light) — a game has to hand-roll its own system ticking those
      fields today; a small opt-in flicker/pulse config on `Light2D`
      itself (or a dedicated `LightFlickerSystem`) would cover the
      common case without every game re-deriving the same noise
      function.
- [ ] Directional/cone lights: `Light2D` is a point light (radial falloff
      in every direction) only — no flashlight-cone or directional-beam
      shape, which the "New engine features (round 2)" item's own
      description named as a concrete use case this doesn't cover yet.

## New engine features (round 2) — Platformer (`engine_platformer`)

- [ ] Ladders/climbing, conveyors, per-tile friction: collision is
      binary solid/one-way/slope today — no variable surface behavior.
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
