# Platformer gameplay (`engine_platformer`)

Genre-specific gameplay logic built on `engine_core` + `engine_flutter`:
gravity, jump, tile/platform collision, patrol/follow AI, combat,
health/respawn, inventory, HUD wiring, movement-driven animation. Kept
out of `engine_core` on purpose — a non-platformer 2D game (top-down,
puzzle) shouldn't be forced to depend on gravity/jump concepts. See
`packages/engine_platformer/lib/src/system_pack.dart` and
`spawn_helpers.dart` for the two entry points below.

## Register components

```dart
registerCoreComponents(world);
registerFlutterComponents(world);
registerPlatformerComponents(world); // Gravity, PlatformBody, PlatformerController,
                                      // Health, Inventory, Weapon, Projectile, etc.
```

`Scene`/`GameRunner` already do the first two for you; you add the
third yourself if you're using `engine_platformer`.

## Spawning: `spawnPlayer` / spawn helpers

`spawn_helpers.dart` replaces the hand-spawned entity + component
boilerplate every platformer needs, without hiding what the components
actually are:

```dart
final player = spawnPlayer(
  world,
  x: 100, y: 100,
  input: inputState,               // InputController's InputState — PlatformerInputSystem reads this
  jumpSpeed: 500,
  atlasId: 'characters', spriteRegion: 'player_idle',
  animations: MovementAnimationSet.fromSequences(idle: ..., walk: ..., jump: ...),
  maxHealth: 100,                  // also attaches Health + a LastCheckpoint at spawn
  startingInventory: {'coin': 0},  // also attaches Inventory
);
```

This attaches `Position`/`Velocity`/`Collider`/`Gravity`/
`PlatformerController` unconditionally, plus `Sprite`/animation/
`Health`/`Inventory` only when you pass the corresponding arguments —
each is independently optional.

## Wiring systems: `installPlatformerSystems`

```dart
installPlatformerSystems(
  world,
  player: player,       // wires PlatformerInputSystem for this entity
  behaviors: behaviors, // BehaviorRegistry — wires AISystem for AI-controlled entities
);
```

This is the single call that gets the ~10 systems' registration order
right — gravity, jump, tile/platform collision, ledge grab, water,
ladder, dash, hitstun, facing, movement/jump animation, health tick,
projectile aging, attack — where getting the order wrong by hand is a
real, documented bug class (see the doc comment on `JumpSystem` for the
concrete regression this caused once: jump consumption running before
tile-based grounding was resolved). Set `includeAnimation: false` for a
headless world with no `Sprite`s at all.

Damage/death/respawn and projectile-vs-target damage are **not** part
of this pack — call them explicitly so *when*/*what* takes damage stays
visible in your own game code:

```dart
installProjectileDamage(world); // needed for both melee and ranged Weapon, since AttackSystem spawns a Projectile under the hood
```

## Combat

`Weapon` (component) + `AttackSystem` fire on an entity's `"attack"`
action or a directly-set `Weapon.attackRequested`; both melee and
ranged weapons spawn a `Projectile` under the hood, which
`ProjectileSystem` ages/expires and `installProjectileDamage` resolves
against `Health` on touch. Helpers in `combat_helpers.dart`:

```dart
damageEntity(world, target, amount);        // applies Health damage + invincibility window, returns whether it killed
healEntity(world, target, amount);
dealDamageOnTouch(world, source, targetTag, amount); // wires a trigger/collision to call damageEntity
```

`Health` is `{current, max, invincibleSeconds}` with `isDead`/
`isInvincible` getters — plain data; `HealthSystem` only ticks
`invincibleSeconds` down, `HitstunSystem` only ticks
`PlatformerController.hitstunSeconds` down. Neither applies damage
itself.

## Checkpoints and respawn

```dart
trackCheckpoints(world, player);           // updates LastCheckpoint as the player touches Checkpoint entities
respawnOnDeath(world, player, onRespawn: ...); // wires Health.isDead -> respawnPlayer at LastCheckpoint
```

See `checkpoint_helpers.dart` for the full set, including manual
`respawnPlayer`.

## AI: patrol/follow/avoidance

Ready-made `Behavior` implementations in `ai/`:
`PatrolBehavior` (waypoint loop), `FollowBehavior` (chase a target
entity within range), `AvoidanceBehavior` (steer around obstacles),
`PathFollowBehavior` (follow an `engine_core` A* path). Register and
attach like any `Behavior` — see [agent-api.md](agent-api.md).

## Animation

`MovementAnimationSet` (idle/walk/jump clips, switched by
`MovementAnimationSystem` from `Velocity`/grounded state) and
`JumpAnimationSet` (finer jump-phase clips — rise/peak/fall — via
`JumpAnimationSystem`, a no-op if an entity has no `JumpAnimationSet`,
so it costs nothing for a game only using the plain single-clip jump
in `MovementAnimationSet`). Both are `engine_platformer`'s decision
layer on top of `engine_flutter`'s generic `AnimationSystem` — see
[rendering.md](rendering.md).

## HUD

```dart
final bar = spawnHealthHudBar(world, source: player, x: 20, y: 20, width: 200, height: 20);
// HealthHudSystem (already in installPlatformerSystems) keeps bar's
// HudBar.value/maxValue synced from player's Health every tick via HealthHudLink.
```

## See also

- [rendering.md](rendering.md) — the `engine_flutter` primitives this package builds on.
- [agent-api.md](agent-api.md) — writing a custom `Behavior` for a new enemy type.
- [`packages/engine_platformer/README.md`](../../packages/engine_platformer/README.md) — full API reference (boss phases, ladders, water physics, dash, wall jump, one-way/slope tiles).
