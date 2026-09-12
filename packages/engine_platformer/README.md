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

## System order

Platformer physics is order-sensitive. Register systems in this order:

```dart
world.addSystem(PlatformerInputSystem(playerId)); // or your own input/AI systems
world.addSystem(AISystem(behaviorRegistry));       // enemy behaviors
world.addSystem(GravitySystem());
world.addSystem(MovementSystem());                 // from engine_core
world.addSystem(PlatformerSystem());               // PlatformBody collision
world.addSystem(TileCollisionSystem());            // TileMap collision
world.addSystem(JumpSystem());                     // must run after both of the above
world.addSystem(FacingSystem());
world.addSystem(MovementAnimationSystem());
world.addSystem(AnimationSystem());                // from engine_flutter, must run after MovementAnimationSystem
world.addSystem(CollisionSystem());                // from engine_core
```

**Why `JumpSystem` goes last of the movement systems**: grounded state
can come from either a `PlatformBody` or a `TileMap` tile, resolved by
two different systems. If jump input were checked before both had run,
a jump off tile-only ground would silently do nothing — a real bug this
package's tests caught (see `PlatformerSystem`'s doc comment).

## Player and enemies

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
    atlasId: 'atlas', spriteRegion: 'player_idle',
  );
  world.addSystem(PlatformerInputSystem(player));

  final behaviors = BehaviorRegistry()
    ..register('patrol', PatrolBehavior(minX: 100, maxX: 300, speed: 60))
    ..register('chase', FollowBehavior(target: player, maxDistance: 200));
  world.addSystem(AISystem(behaviors));

  spawnEnemy(world, x: 150, y: 40, behaviorId: 'patrol', atlasId: 'atlas', spriteRegion: 'enemy');
}
```

`spawnPlayer`/`spawnEnemy` wire up the component boilerplate (Position,
Velocity, Collider, Gravity, PlatformerController, AIState, optional
Sprite) — they don't hide *how* movement/physics work, they just save
you writing the same six `world.storeOf<T>().set(...)` calls for every
character.

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

```dart
world.storeOf<MovementAnimationSet>().set(playerId, MovementAnimationSet(
  idle: AnimationClip('idle', ['idle_0', 'idle_1'], frameDurationSeconds: 0.2),
  walk: AnimationClip('walk', ['walk_0', 'walk_1', 'walk_2'], frameDurationSeconds: 0.1),
  jump: AnimationClip('jump', ['jump_0']),
));
world.addSystem(FacingSystem());
world.addSystem(MovementAnimationSystem());
world.addSystem(AnimationSystem()); // from engine_flutter — must run after
```

`MovementAnimationSystem` picks idle/walk/jump from velocity and
`PlatformerController.grounded`, swapping `AnimationState`'s clip only
when the picked clip actually changes (so it never resets playback
mid-loop). `FacingSystem` flips `Sprite.scaleX` to face the direction
of horizontal movement, holding the last facing while idle.

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
