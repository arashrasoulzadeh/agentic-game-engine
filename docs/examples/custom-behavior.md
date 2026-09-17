# Recipe: define a custom `Behavior`

The built-in `PatrolBehavior`/`FollowBehavior`/`AvoidanceBehavior`/
`PathFollowBehavior` (`engine_platformer`) cover common cases; for
anything else — a boss with attack phases, an LLM-backed NPC, a
scripted cutscene actor — implement `Behavior` directly. See
[concepts/agent-api.md](../concepts/agent-api.md) for the full
sandbox model this fits into.

## A simple "flee when low health" behavior

```dart
class FleeWhenHurtBehavior implements Behavior {
  FleeWhenHurtBehavior({required this.fleeToX, this.healthThreshold = 0.3, this.speed = 100});

  final double fleeToX;
  final double healthThreshold; // fraction of max health
  final double speed;

  @override
  Action decide(WorldView view, EntityId self) {
    final health = view.component<Health>(self);
    final pos = view.component<Position>(self);
    if (health == null || pos == null) return const NoOpAction();

    if (health.current / health.max > healthThreshold) {
      return const NoOpAction(); // not hurt enough to flee yet
    }

    final direction = fleeToX > pos.x ? 1.0 : -1.0;
    return SetVelocityAction(self, direction * speed, 0);
  }
}
```

```dart
behaviors.register('flee-when-hurt', FleeWhenHurtBehavior(fleeToX: 50));
world.storeOf<AIState>().set(bossId, AIState('flee-when-hurt'));
```

## Carrying state between ticks: `AIState.memory`

```dart
class CountdownBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) {
    final state = view.component<AIState>(self)!;
    final ticksLeft = (state.memory['ticksLeft'] as int?) ?? 60;
    if (ticksLeft <= 0) {
      // do something, e.g. return an attack action
    }
    state.memory['ticksLeft'] = ticksLeft - 1; // AIState isn't part of
    // the read-only contract — only World mutation is guarded, so
    // writing back into the AIState you already hold a reference to is fine.
    return const NoOpAction();
  }
}
```

## A domain-specific `Action`

If none of the engine's built-in `Action`s (`NoOpAction`,
`SetVelocityAction`) fit, define your own — this is the intended
extension point, not a special case:

```dart
class FireProjectileAction implements Action {
  FireProjectileAction(this.shooter, this.targetX, this.targetY);
  final EntityId shooter;
  final double targetX, targetY;

  @override
  void apply(World world) {
    // spawnProjectile / whatever your game's projectile setup is —
    // this is the one place allowed to mutate World for this decision.
  }
}
```

Return it from `decide`; `AISystem` calls `apply(world)` for you after
every behavior's decision each tick.
