# Changelog

All notable changes to this project are documented in this file, newest
first. `v0.1.0` is tagged locally (see [TODO.md](TODO.md)) but not yet
pushed to the remote or published to pub.dev — still consumed via the
self-referencing git-dependency pattern documented in each package's
pubspec.yaml.

## [Unreleased]

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
