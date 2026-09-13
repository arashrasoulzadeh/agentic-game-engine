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
