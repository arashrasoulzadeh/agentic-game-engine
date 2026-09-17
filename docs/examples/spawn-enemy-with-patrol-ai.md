# Recipe: spawn an enemy with patrol AI

```dart
final behaviors = BehaviorRegistry();
behaviors.register(
  'guard-patrol',
  PatrolBehavior(minX: 200, maxX: 400, speed: 50, avoidLedges: true),
);

final guard = spawnEnemy(
  world,
  x: 300, y: 300,
  behaviorId: 'guard-patrol',
  affectedByGravity: true, // attaches Gravity + PlatformerController too
  maxHealth: 30,
  atlasId: 'characters',
  spriteRegion: 'guard_idle',
);

// AISystem must be running for AIState-tagged entities to actually move —
// installPlatformerSystems(world, behaviors: behaviors) wires this for you,
// or add it directly: world.addSystem(AISystem(behaviors));
```

`spawnEnemy` attaches `AIState('guard-patrol')` under the hood, which
is what tells `AISystem` which registered `Behavior` drives this
entity — see [concepts/agent-api.md](../concepts/agent-api.md).

`PatrolBehavior.avoidLedges: true` makes the guard turn around at a gap
in the ground even if the gap is inside its `[minX, maxX]` range,
instead of only turning at the authored bounds — a safety net on top of
the range, not a replacement for it.

## Chase instead of patrol: `FollowBehavior`

```dart
behaviors.register('chase', FollowBehavior(target: player, speed: 80, maxDistance: 250));
```

`maxDistance` (default: unlimited) caps how far the follower engages
from; `stopDistance` (default `4`) is how close it stops approaching;
`requireLineOfSight` (default `false`) additionally requires a clear
raycast to the target before following — see
`packages/engine_platformer/lib/src/ai/follow_behavior.dart`.

## Writing your own instead

If neither built-in fits, implement `Behavior` directly — see
[custom-behavior.md](custom-behavior.md).
