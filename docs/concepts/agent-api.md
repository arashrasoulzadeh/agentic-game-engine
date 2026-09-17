# The agent-facing API: `Behavior` + `WorldView` + `AISystem`

This is the engine's other AI-agent-friendly pillar (alongside
[content-as-data.md](content-as-data.md)): a sandbox for a runtime
agent/NPC to *drive an entity during simulation* — whether that agent
is a hand-written state machine, a rule-based patrol AI, or an
LLM-backed decision-maker — without any path to corrupting world state.

## Why a sandbox

A behavior that could freely mutate `World` could, by a bug or a bad
LLM tool call, break invariants another system depends on (move an
entity outside the map, delete a component another system reads
unconditionally, etc.). So a `Behavior` never sees the real, mutable
`World` — only a read-only `WorldView` — and can only *propose* a
change by returning an `Action`, which `AISystem` (not the behavior
itself) applies against the real `World`.

```
Behavior.decide(WorldView, EntityId self) -> Action
                                                 |
                                                 v
                                    AISystem: action.apply(world)
```

## `WorldView`: read-only queries

`packages/engine_core/lib/src/ecs/world_view.dart`. Wraps a `World` and
exposes only queries — no setters:

```dart
class MyBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) {
    final myPos = view.component<Position>(self);
    if (myPos == null) return const NoOpAction();

    for (final other in view.entitiesWith<Position>()) {
      if (other == self) continue;
      // read-only inspection of other entities is fine — mutation isn't possible here
    }

    return const NoOpAction();
  }
}
```

Useful queries: `component<T>(id)`, `hasComponent<T>(id)`,
`entitiesWith<T>()`, `entitiesWithAll<A, B>()`, and a closest-entity
helper — see the full list in `world_view.dart` or
`packages/engine_core/README.md`'s agent-API section.

## `Action`: the only way to cause a change

```dart
abstract class Action {
  void apply(World world);
}
```

The engine ships generic actions (e.g. `NoOpAction`,
`SetVelocityAction` in `packages/engine_core/lib/src/ai/set_velocity_action.dart`)
plus whatever your game defines itself — a game-specific `Action`
subclass is how you extend this without the engine needing to know
about your domain logic:

```dart
class TakeDamageAction implements Action {
  TakeDamageAction(this.target, this.amount);
  final EntityId target;
  final double amount;

  @override
  void apply(World world) {
    // this is the one place allowed to actually mutate World
    final health = world.storeOf<Health>().get(target);
    // ...
  }
}
```

## `Behavior` + `BehaviorRegistry`

```dart
abstract class Behavior {
  Action decide(WorldView view, EntityId self);
}
```

Behaviors carry logic (closures, state machines) so — unlike plain-data
components — they're registered under a string id rather than embedded
in JSON, and `AIState.behaviorId` references that id:

```dart
final behaviors = BehaviorRegistry();
behaviors.register('patrol', PatrolBehavior(waypoints: [...]));
world.addSystem(AISystem(behaviors));

final enemy = world.spawn();
world.storeOf<AIState>().set(enemy, AIState('patrol'));
```

`AIState.memory` is a free-form JSON-serializable blackboard (a
waypoint index, a cooldown timer) a behavior can carry state in between
ticks without needing its own component type — mutate it directly on
the `AIState` you read via `view.component<AIState>(self)` inside
`decide`, since `AIState` itself isn't part of the read-only contract
(only the `World` mutation path is guarded).

## `AISystem`

Runs every `AIState`-tagged entity once per tick: resolves its
`behaviorId` via the registry, calls `decide`, applies the returned
`Action`. Builds one `WorldView` per tick (not per entity) — every
behavior that tick sees the same consistent snapshot, so ordering
between two behaviors' decisions within the same tick can't matter.

## `engine_platformer`'s ready-made behaviors

`PatrolBehavior`, `FollowBehavior`, `AvoidanceBehavior`,
`PathFollowBehavior` (`packages/engine_platformer/lib/src/ai/`) are
concrete `Behavior` implementations for common enemy AI — read one of
these as a worked example of writing your own.

## See also

- [ecs.md](ecs.md) — `World`/`ComponentStore`/`System` underneath all of this.
- [content-as-data.md](content-as-data.md) — the other read/write path (patching from outside simulation, vs. deciding during it).
- [examples/custom-behavior.md](../examples/custom-behavior.md) — a focused, minimal worked example.
- [`packages/engine_core/README.md`](../../packages/engine_core/README.md)'s "The agent-facing API" section.
