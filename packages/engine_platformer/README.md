# engine_platformer

2D-platformer-genre gameplay built on
[engine_core](../engine_core/README.md) and
[engine_flutter](../engine_flutter/README.md): gravity, jump (with
coyote time, jump buffering, air jumps, wall jumps, jump cut, and
ledge grab/mantle all opt-in — see
[Movement feel](#movement-feel-platformercontroller) below),
tile/platform collision (including ladders, conveyors, and per-tile
friction — see [Tile-based terrain
features](#tile-based-terrain-features)), player and enemy spawn
helpers, patrol/follow/path-follow/avoidance AI behaviors, and
facing/movement-driven animation.

Kept separate from `engine_core` on purpose: gravity and jump aren't
universal 2D concepts (a top-down or puzzle game has no use for them),
so a non-platformer game shouldn't be forced to depend on this package.
`TileMap` itself stays in `engine_core` since tile grids *are* general
enough for other genres — only the platformer-specific *collision
logic* against it lives here.

## Install

```yaml
dependencies:
  engine_platformer:
    git:
      url: https://github.com/arashrasoulzadeh/agentic-game-engine.git
      path: packages/engine_platformer
      ref: main
```

## Quick start: `installPlatformerSystems`

Platformer physics is order-sensitive (see below for why) — instead of
hand-writing ~10 `world.addSystem(...)` calls in the right order, call
`installPlatformerSystems` once:

```dart
final input = InputController();

@override
InputController createInputController() => input;

@override
void populateWorld(World world) {
  registerPlatformerComponents(world); // alongside registerCoreComponents/registerFlutterComponents, which GameRunner already calls

  final player = spawnPlayer(
    world,
    x: 40, y: 40,
    input: input.state,
    jumpSpeed: 500,
    atlasId: 'atlas',
    spriteRegion: 'idle',
    animations: MovementAnimationSet.fromSequences(
      idleRegion: 'idle',
      walkPrefix: 'walk', walkFrameCount: 8,
      jumpPrefix: 'jump', jumpFrameCount: 4,
    ),
  );

  final behaviors = BehaviorRegistry()
    ..register('patrol', PatrolBehavior(minX: 100, maxX: 300, speed: 60))
    ..register('chase', FollowBehavior(target: player, maxDistance: 200));

  installPlatformerSystems(world, player: player, behaviors: behaviors);

  spawnEnemy(
    world,
    x: 150, y: 40,
    behaviorId: 'patrol',
    atlasId: 'atlas', spriteRegion: 'enemy_idle',
  );
}
```

`spawnPlayer`/`spawnEnemy` wire up the component boilerplate (Position,
Velocity, Collider, Gravity, PlatformerController, AIState, optional
Sprite + `MovementAnimationSet`/`AnimationState`) — they don't hide
*how* movement/physics work, they just save you writing the same calls
for every character. Need a system this pack doesn't cover (a custom
input system, a score system)? Just `world.addSystem(...)` it yourself
before or after — `installPlatformerSystems` doesn't own the whole list,
only the platformer-genre part of it.

## System order (what `installPlatformerSystems` does for you)

```dart
world.addSystem(PlatformerInputSystem(playerId)); // or your own input system
world.addSystem(AISystem(behaviorRegistry));       // enemy behaviors
world.addSystem(GravitySystem());
world.addSystem(MovementSystem());                 // from engine_core
world.addSystem(PlatformerSystem());               // PlatformBody collision
world.addSystem(TileCollisionSystem());            // TileMap collision (incl. ladders/conveyors/friction)
world.addSystem(JumpSystem());                     // must run after both of the above
world.addSystem(LadderSystem(playerId));           // climb: only while player is given
world.addSystem(LedgeGrabSystem(playerId));        // grab/mantle: only while player is given, runs after LadderSystem
world.addSystem(DashSystem());
world.addSystem(CollisionSystem());                // from engine_core
world.addSystem(HealthSystem());                   // ticks Health.invincibleSeconds down
world.addSystem(HitstunSystem());                  // ticks PlatformerController.hitstunSeconds down
world.addSystem(HealthHudSystem());                // syncs any HudBar wired to a Health via spawnHealthHudBar
world.addSystem(ProjectileSystem());                // ages/expires Projectiles
world.addSystem(FacingSystem());
world.addSystem(MovementAnimationSystem());
world.addSystem(AnimationSystem());                // from engine_flutter, must run after MovementAnimationSystem
world.addSystem(AnimationTransitionSystem());      // fades out AnimationTransition ghosts from a crossfaded clip swap
```

The last four (`HealthSystem` through `ProjectileSystem`) are
harmless no-ops for a game that doesn't use `Health`/hitstun/the HUD
helpers/`Projectile` yet — they're included unconditionally so you
don't have to remember to add them later when you do.

**Why `JumpSystem` goes after both `PlatformerSystem` and
`TileCollisionSystem`**: grounded state can come from either a
`PlatformBody` or a `TileMap` tile, resolved by two different systems.
If jump input were checked before both had run, a jump off tile-only
ground would silently do nothing — a real bug this package's tests
caught (see `PlatformerSystem`'s doc comment) and that
`installPlatformerSystems` now makes structurally impossible to get
wrong by hand.

## Movement feel (`PlatformerController`)

Every field below is opt-in and defaults to "off, exactly like the
original strict grounded-only jump" — set only the ones your game
actually wants; a `PlatformerController()` with no arguments behaves
identically to the very first version of this component.
`spawnPlayer`'s own parameters only cover `jumpSpeed` (the rest would
be a lot of rarely-all-used parameters to thread through one helper) —
set anything else directly on the component after spawning:

```dart
final player = spawnPlayer(world, x: 40, y: 40, input: input.state, jumpSpeed: 500);

final controller = world.storeOf<PlatformerController>().get(player)!;
controller.coyoteTimeSeconds = 0.1;      // still counts as grounded briefly after walking off a ledge
controller.jumpBufferSeconds = 0.15;     // a jump pressed just before landing still fires on landing
controller.maxAirJumps = 1;              // a standard double jump
controller.wallJumpPushSpeed = 220;      // jumping while touching a wall pushes away from it
controller.wallSlideMaxFallSpeed = 80;   // caps fall speed while airborne and touching a wall
controller.jumpCutMultiplier = 0.5;      // releasing jump early while ascending shortens the arc
controller.dashSpeed = 400;              // DashSystem: a horizontal burst on dashRequested
controller.dashDurationSeconds = 0.15;
controller.climbSpeed = 140;             // LadderSystem: hold up/down on a TileMap.ladderTileIds tile to climb
controller.ledgeGrabEnabled = true;      // LedgeGrabSystem: grab a wall's top edge instead of sliding past it
```

- **Coyote time / jump buffering** (`coyoteTimeSeconds`/
  `jumpBufferSeconds`) — the two classic "feels fair" jump-timing
  forgiveness windows. Both `0` by default (the original strict
  behavior: a jump only fires the exact tick it's requested *and*
  grounded).
- **Air jumps** (`maxAirJumps`) — extra jumps beyond the first while
  airborne, reset on the next ground contact.
- **Wall jump / wall slide** (`wallJumpPushSpeed`/
  `wallSlideMaxFallSpeed`) — read `touchingWallLeft`/`touchingWallRight`
  (set by `PlatformerSystem`/`TileCollisionSystem` from whichever of a
  `PlatformBody` or a solid `TileMap` tile the entity is touching).
- **Jump cut** (`jumpCutMultiplier`) — a one-shot `Velocity.y` clamp
  applied the tick the jump button is released while still ascending,
  for variable jump height from a single input.
- **Dash** (`dashSpeed`/`dashDurationSeconds`, plus
  `dashRequested`/`DashSystem`) — one dash per ground contact by
  default; set `dashRequested = true` from your own input code (or use
  `PlatformerInputSystem`'s `dashAction`, unbound by default since it's
  not in `InputController.defaultBindings()`).
- **Hitstun/knockback** (`hitstunSeconds`, set via `damageEntity`'s
  `hitstunSeconds` parameter or directly) — freezes
  `PlatformerInputSystem`'s input handling for that entity, so a
  knockback impulse isn't immediately overridden by the player still
  holding a direction; counted down by `HitstunSystem`.
- **Ladder climbing** (`climbSpeed`, plus `TileMap.ladderTileIds` and
  `LadderSystem`) — `0` disables it entirely. Only engages while up or
  down is actually held on a ladder tile — merely brushing past one
  (e.g. mid-jump) never affects `Velocity.y`.
- **Ground friction** (via `TileMap.frictionByTileId`, read into the
  runtime `groundFriction` field) — a tile id mapped below `1.0` makes
  grounded horizontal velocity *slide* toward the input target instead
  of snapping instantly (an icy patch); untagged tiles (the default for
  every id) keep the original instant-snap feel.
- **Conveyor tiles** (`TileMap.conveyorSpeedByTileId`) — a tile id
  mapped to a px/s value nudges `Position.x` directly for anything
  resolved grounded on it that tick, independent of the entity's own
  input.
- **Ledge grab / mantle** (`ledgeGrabEnabled`, plus `LedgeGrabSystem`)
  — an airborne entity touching a wall right at its top edge (open
  space above both the wall and the entity) grabs on instead of
  sliding past; hold up/jump to climb up onto the ledge, or down to let
  go. See `LedgeGrabSystem`'s doc comment for exactly how the ledge
  geometry is detected (a tile-grid approximation, not sub-pixel-precise
  contact).

## Behaviors

- **`PatrolBehavior(minX, maxX, speed)`** — walks back and forth,
  flipping direction at the bounds. Direction persists in
  `AIState.memory['dir']`.
- **`FollowBehavior(target, speed, maxDistance?, stopDistance,
  requireLineOfSight)`** — chases another entity horizontally (never
  touches vertical velocity, so it doesn't fight gravity/jump).
  `maxDistance` makes it an aggro range rather than an infinite chase;
  `requireLineOfSight` (off by default) stops the chase whenever a
  `TileMap` wall is between the two, via `WorldView.hasLineOfSight`.
- **`PathFollowBehavior(path, speed, arriveDistance)`** — walks a
  precomputed route from `findPath` (`engine_core`) one waypoint at a
  time, horizontal movement only. Doesn't decide *when* to jump onto a
  higher waypoint itself — that's a game-specific rule you check
  against `currentTarget`.
- **`AvoidanceBehavior(inner, {avoidRadius, avoidStrength})`** — wraps
  any of the above (or your own `Behavior`) and blends in a horizontal
  separation push away from other nearby `AIState`-carrying entities,
  on top of whatever the wrapped behavior decides, so a pack of enemies
  whose paths cross spreads out instead of overlapping/stacking:
  ```dart
  behaviors.register('patrol', AvoidanceBehavior(
    PatrolBehavior(minX: 100, maxX: 300, speed: 60),
  ));
  ```
  Only pushes away from entities that also carry `AIState` — never the
  player, a coin, or anything else without one.

All four are ordinary `Behavior` implementations — write your own the
same way for anything these don't cover (see
[engine_core's README](../engine_core/README.md#3-runtime-agentsnpcs--worldview--behavior--aisystem)
for the `Behavior`/`WorldView` contract).

## Animation

`MovementAnimationSet.fromSequences` builds idle/walk/jump clips from a
naming convention (`walk_0`, `walk_1`, ... — see `AnimationClip.sequence`
in `engine_flutter`) instead of spelling out each `AnimationClip` by
hand — this is what `spawnPlayer`'s `animations:` argument in the
quick-start example above uses. For anything not covered by the naming
convention, build `MovementAnimationSet` directly:

```dart
world.storeOf<MovementAnimationSet>().set(playerId, MovementAnimationSet(
  idle: AnimationClip('idle', ['idle_0', 'idle_1'], frameDurationSeconds: 0.2),
  walk: AnimationClip('walk', ['walk_0', 'walk_1', 'walk_2'], frameDurationSeconds: 0.1),
  jump: AnimationClip('jump', ['jump_0']),
));
```

(`installPlatformerSystems`/`FacingSystem`+`MovementAnimationSystem`+
`AnimationSystem` still need to be registered either way —
`installPlatformerSystems` does this for you when `includeAnimation`
is left at its default `true`.)

`MovementAnimationSystem` picks idle/walk/jump from velocity and
`PlatformerController.grounded`, swapping `AnimationState`'s clip only
when the picked clip actually changes (so it never resets playback
mid-loop). `FacingSystem` flips `Sprite.scaleX` to face the direction
of horizontal movement, holding the last facing while idle.

## Reacting to collisions (coins, hitting an enemy, ...)

`engine_core` ships `onCollisionBetween`/`onCollisionInvolving`/
`onCollisionWithAny` extension methods on `World`, replacing the manual
"check both orderings of `CollisionEvent.a`/`.b`" boilerplate every
handler otherwise repeats:

```dart
world.onCollisionInvolving(player, (other) {
  if (other == enemy) { /* respawn */ }
});

final coins = <EntityId>{...};
world.onCollisionWithAny(coins, (coin, _) {
  coins.remove(coin);
  world.destroy(coin);
});
```

See [engine_core's README](../engine_core/README.md#events) for the
full set.

## Damage/health/combat

```dart
final player = spawnPlayer(world, x: 40, y: 40, input: input.state, maxHealth: 100);
final enemy = spawnEnemy(world, x: 150, y: 40, behaviorId: 'patrol', maxHealth: 20);

dealDamageOnTouch(world, {enemy}, 10); // touching this enemy damages the player
```

`maxHealth` on `spawnPlayer`/`spawnEnemy` attaches a `Health`
component (full at spawn); `spawnPlayer` also seeds a `LastCheckpoint`
at the spawn point. `HealthSystem` (part of `installPlatformerSystems`)
only ticks `Health.invincibleSeconds` down each tick — damage/death
stay explicit calls you make yourself, not hidden system behavior:

- **`damageEntity(world, id, amount, {invincibilitySeconds,
  source, knockbackSpeed, hitstunSeconds})`** — subtracts health,
  starts an invincibility window (further damage is a no-op until it
  expires), and emits `DeathEvent` exactly once when health first
  reaches 0. `knockbackSpeed` (`0` default) pushes the entity away from
  `source`; `hitstunSeconds` (`0` default) sets
  `PlatformerController.hitstunSeconds`, freezing that entity's input
  handling until `HitstunSystem` counts it down — both no-ops unless
  set, and `hitstunSeconds` is itself a no-op for an entity with no
  `PlatformerController` (e.g. an AI-only enemy).
- **`healEntity(world, id, amount)`** — restores health, clamped to max.
- **`dealDamageOnTouch(world, hazards, amount, {invincibilitySeconds,
  knockbackSpeed, hitstunSeconds})`** — the common case (spikes, enemy
  contact damage) in one call, via `World.onCollisionWithAny` under the
  hood; forwards `knockbackSpeed`/`hitstunSeconds` straight to
  `damageEntity`, using whichever hazard was actually touched as the
  knockback source. For anything more specific (conditional damage,
  different amounts per hazard), call `damageEntity` directly from your
  own collision listener instead.

## Checkpoints and respawn

```dart
trackCheckpoints(world, player);
respawnOnDeath(world, player, fallbackX: 40, fallbackY: 40);

final checkpoint = world.spawn();
world.storeOf<Position>().set(checkpoint, Position(500, 40));
world.storeOf<Collider>().set(checkpoint, Collider(16));
world.storeOf<Checkpoint>().set(checkpoint, Checkpoint('cp1'));
```

`trackCheckpoints` listens for the player touching any `Checkpoint`
entity and records its `Position` as the player's `LastCheckpoint`.
`respawnOnDeath` wires `respawnPlayer` (resets position/velocity/health
to the last checkpoint, or `fallbackX`/`fallbackY` if none was touched
yet) to fire automatically on `DeathEvent` — skip it and call
`respawnPlayer` directly if you need a delay or a death animation
first.

## Collectibles/inventory

```dart
final player = spawnPlayer(world, x: 0, y: 0, input: input.state, startingInventory: {'coin': 0});

final coin = world.spawn();
world.storeOf<Position>().set(coin, Position(200, 40));
world.storeOf<Collider>().set(coin, Collider(8));
dealPickupOnTouch(world, {coin}, 'coin');
```

`spawnPlayer`'s optional `startingInventory` attaches an `Inventory`
(item id -> count) pre-populated with those counts. `dealPickupOnTouch`
is the common case (a coin/key/power-up touched by anyone with an
`Inventory`) in one call via `World.onCollisionWithAny`; pass
`destroyOnCollect: false` for something reusable instead of consumed
(a lever, a repeatable trigger). For anything more specific, call
`collectItem(world, holder, itemId, amount: n)` directly from your own
collision listener — it's a no-op if `holder` has no `Inventory`, safe
to call without checking first, and emits `ItemCollectedEvent` exactly
when it actually adds something.

## Tile-based terrain features

Beyond plain solid/one-way/slope tiles, `TileMap` (from `engine_core`)
carries three more opt-in, per-tile-id collision behaviors that
`TileCollisionSystem` reads — all empty/default by construction, so an
untagged tile id behaves exactly as before:

```dart
TileMap(
  cols: 20, rows: 10, tileWidth: 32, tileHeight: 32,
  tiles: [...],
  solidTileIds: {1},
  ladderTileIds: {2},                          // climbable via LadderSystem (needs controller.climbSpeed > 0)
  conveyorSpeedByTileId: {3: 80},               // px/s pushed while grounded on tile id 3
  frictionByTileId: {4: 0.1},                   // grounded velocity slides instead of snapping on tile id 4
);
```

See [Movement feel](#movement-feel-platformercontroller) above for how
each of these connects to `PlatformerController`.

## Tilemaps vs. platform entities

Two ways to build level geometry, usable together:

- **`TileMap`** + `TileCollisionSystem` — a grid, good for most level
  geometry. `solidTileIds`/`oneWayTileIds` mark which tile ids collide
  and how; `slopeUpRightTileIds`/`slopeUpLeftTileIds` add walkable
  diagonal ramps.
- **`PlatformBody`** + `PlatformerSystem` — one entity per platform,
  good for moving platforms or geometry that doesn't fit a grid.

Both support `oneWay` (landable from above only, never blocks from
below/the sides) and solid (full circle-vs-AABB resolution: blocks
landing, side contact, and hitting the underside).

## Testing

```bash
flutter test
flutter analyze --fatal-infos
```

Test coverage is 100% (line coverage via `flutter test --coverage`,
producing `coverage/lcov.info`).

## Benchmarks

`benchmark/` holds `package:benchmark_harness` benchmarks for this
package's systems, run via `flutter test` (not plain `dart run` — this
package depends on the Flutter SDK transitively through
`engine_flutter`, which plain `dart run` can't resolve):

```bash
flutter test benchmark/tile_collision_benchmark.dart
flutter test benchmark/full_pipeline_benchmark.dart
```

("No tests found" at the end is expected — these are `main()`-only
scripts, not `test()`-based suites; the numbers print before that.)
See `engine_core`'s README for that package's own benchmarks
(`CollisionSystem`, `ParticleSystem`, entity spawn/destroy churn) and
TODO.md's Performance section for what these have found so far.
