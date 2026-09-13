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
- [x] Collectible/inventory helpers: `Inventory` component (item id ->
      count), `collectItem`/`dealPickupOnTouch` helpers (mirroring
      `damageEntity`/`dealDamageOnTouch`'s pattern) + `ItemCollectedEvent`.
      `spawnPlayer` grows an optional `startingInventory`.
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
- [ ] **To improve**: `EngineView`'s sprite pass (`_EnginePainter.paint`
      in `packages/engine_flutter/lib/src/engine_view.dart`) does one
      `canvas.save()`/`translate()`/`scale()`/`drawImageRect()`/
      `restore()` *per sprite*, every frame. `Canvas.drawAtlas` (or
      grouping sprites by shared atlas and building one `RSTransform`
      list) draws many sprites from the same source image in a single
      call with no per-sprite save/restore — the standard Flutter
      technique for sprite-heavy 2D scenes. Worth an
      `engine_flutter`-side benchmark (none exists yet — these need a
      `flutter test`-based harness, see `engine_platformer/benchmark`'s
      README note on why) before committing to the rewrite, since it
      only pays off once sprite counts get large enough that
      save/restore overhead dominates over the actual blit cost.
- [ ] **To evaluate**: `WorldView.nearestWithPosition`
      (`packages/engine_core/lib/src/world_view.dart`) is a linear scan
      over every `Position`, called potentially once per AI-driven
      entity per tick via a `Behavior`. Already documented in its own
      doc comment as "fine at the entity counts a single AI query
      needs" — no action unless a game with many simultaneous AI
      queries per tick shows this mattering in a benchmark; noted here
      so it's not forgotten as a candidate if that day comes (a
      `SpatialHash`-backed nearest-neighbor query would be the fix).
