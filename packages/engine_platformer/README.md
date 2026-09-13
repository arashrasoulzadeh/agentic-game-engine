# engine_platformer

2D-platformer-genre gameplay built on
[engine_core](../engine_core/README.md) and
[engine_flutter](../engine_flutter/README.md): gravity, jump, tile/platform
collision, player and enemy spawn helpers, patrol/follow AI behaviors,
and facing/movement-driven animation.

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
world.addSystem(PlatformerInputSystem(playerId)); // or your own input/AI systems
world.addSystem(AISystem(behaviorRegistry));       // enemy behaviors
world.addSystem(GravitySystem());
world.addSystem(MovementSystem());                 // from engine_core
world.addSystem(PlatformerSystem());               // PlatformBody collision
world.addSystem(TileCollisionSystem());            // TileMap collision
world.addSystem(JumpSystem());                     // must run after both of the above
world.addSystem(CollisionSystem());                // from engine_core
world.addSystem(HealthSystem());                   // ticks Health.invincibleSeconds down
world.addSystem(FacingSystem());
world.addSystem(MovementAnimationSystem());
world.addSystem(AnimationSystem());                // from engine_flutter, must run after MovementAnimationSystem
```

**Why `JumpSystem` goes after both `PlatformerSystem` and
`TileCollisionSystem`**: grounded state can come from either a
`PlatformBody` or a `TileMap` tile, resolved by two different systems.
If jump input were checked before both had run, a jump off tile-only
ground would silently do nothing — a real bug this package's tests
caught (see `PlatformerSystem`'s doc comment) and that
`installPlatformerSystems` now makes structurally impossible to get
wrong by hand.

## Behaviors

- **`PatrolBehavior(minX, maxX, speed)`** — walks back and forth,
  flipping direction at the bounds. Direction persists in
  `AIState.memory['dir']`.
- **`FollowBehavior(target, speed, maxDistance?, stopDistance)`** —
  chases another entity horizontally (never touches vertical velocity,
  so it doesn't fight gravity/jump). `maxDistance` makes it an aggro
  range rather than an infinite chase.

Both are ordinary `Behavior` implementations — write your own the same
way for anything these don't cover (see
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

- **`damageEntity(world, id, amount, {invincibilitySeconds})`** —
  subtracts health, starts an invincibility window (further damage is a
  no-op until it expires), and emits `DeathEvent` exactly once when
  health first reaches 0.
- **`healEntity(world, id, amount)`** — restores health, clamped to max.
- **`dealDamageOnTouch(world, hazards, amount, {invincibilitySeconds})`**
  — the common case (spikes, enemy contact damage) in one call, via
  `World.onCollisionWithAny` under the hood. For anything more specific
  (conditional damage, different amounts per hazard), call
  `damageEntity` directly from your own collision listener instead.

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

## Tilemaps vs. platform entities

Two ways to build level geometry, usable together:

- **`TileMap`** (from `engine_core`) + `TileCollisionSystem` — a grid,
  good for most level geometry. `solidTileIds`/`oneWayTileIds` mark
  which tile ids collide and how.
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
