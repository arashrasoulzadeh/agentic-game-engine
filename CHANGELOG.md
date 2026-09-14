# Changelog

All notable changes to this project are documented in this file, newest
first. `v0.1.0` is tagged locally (see [TODO.md](TODO.md)) but not yet
pushed to the remote or published to pub.dev — still consumed via the
self-referencing git-dependency pattern documented in each package's
pubspec.yaml.

## [Unreleased]

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
- **Flat, artificial-looking light falloff + hard, faceted shadow
  edges**: reveal/tint gradients now use a 3-stop falloff (bright core,
  gentler tail) instead of a flat 2-stop linear dim, and a shadow-
  casting/cone light's visibility-polygon edges get a small blur
  (applied once per light per frame, not per sampled ray, so it costs
  nothing extra as `shadowRayCount` scales) instead of a hard cutoff.

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
