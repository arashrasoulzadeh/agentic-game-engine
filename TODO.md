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
- [ ] Tweening/easing helpers: a small `Tween<T>`/interpolation utility
      (position, scale, alpha; a handful of easing curves) for UI and
      one-off gameplay animation that doesn't fit the frame-based
      `AnimationClip`/`AnimationState` system (e.g. a menu transition,
      a screen-shake, a damage-flash). Likely `engine_core`-side data
      (genre-general) with any Flutter-curve-conversion glue in
      `engine_flutter`.
- [ ] Save-slot UI helpers: a ready-made save/load menu widget in
      `engine_flutter` building on the existing `SaveGame` (slots,
      `hasSave`, `deleteSave`) so a game doesn't have to hand-roll a
      slot-picker screen — the "menu" analogue of what `OnScreenControls`
      already is for touch input.
- [ ] Basic scene/screen management: a `Scene`/`Screen` abstraction (or
      a thin wrapper over `Navigator`) for switching between menu/
      gameplay/pause/game-over without each game hand-rolling its own
      `Stack`/`Navigator` logic on top of `GameRunner`.

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
- [ ] Collectible/inventory helpers: pickup helpers (coins, keys,
      power-ups) building on the existing `onCollisionWithAny`/
      `dealDamageOnTouch`-style collision helpers, plus a simple
      `Inventory` component (item id -> count) a player can carry.
- [ ] Update `engine_cli`'s `default_game` template to use
      `engine_platformer` (spawnPlayer + a small tile level) instead of
      the current bouncing-circle stress-test demo, now that a real
      platformer starting point exists

## Tooling / release

- [ ] Cut a real `v0.1.0` git tag once the API stops churning; update
      `engine_flutter`'s self-referencing `engine_core` git ref to match
      (see the KNOWN LIMITATION comment in
      `packages/engine_flutter/pubspec.yaml`)
- [ ] Publish `engine_core`/`engine_flutter`/`engine_cli` to pub.dev —
      removes the git-ref-matching constraint entirely via normal semver
- [ ] Test on a real Android/iOS device (or at least a release build) —
      everything so far has only been verified on Flutter web debug
      builds; orientation lock, lifecycle pause/resume, and real-world
      performance are unverified outside that

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
- [ ] **To fix**: `CollisionSystem` degrades worse than linearly as
      entity *density* (entities per spatial-hash cell) rises, not just
      as entity count rises. `collision_system_benchmark.dart` (packs
      entities into a fixed-size world so density scales with count)
      measured roughly 100 -> 1,000 -> 5,000 entities costing
      ~1ms -> ~13ms -> ~2.5s per `step()` on this machine — the last
      jump is ~193x for a 5x entity increase, not the ~5x a linear
      (let alone the intended near-linear spatial-hash) scaling would
      predict. Root cause is almost certainly `SpatialHash`'s fixed
      default `cellSize` (24): `forEachNearbyPair`'s cost per cell is
      quadratic in that cell's occupancy, so a crowded scene without a
      cell size tuned to its entity size/density pays for every pair in
      the crowded cells combinatorially. Candidate fixes to evaluate
      here later: auto-size `cellSize` from typical `Collider.radius`
      in `World`, let `CollisionSystem` reject/cap absurdly large
      per-cell buckets with a documented tradeoff, or add a
      broad-phase pass that subdivides an overcrowded cell instead of
      brute-forcing its pairs. Reproduce with
      `dart run benchmark/collision_system_benchmark.dart` in
      `engine_core` before/after any attempted fix.
