# AI: behavior trees and state machines

Both are **data**: JSON that an `AIState` component carries, run each step by a system.
The [studio](../studio/user-guide.md#graphs) edits and exports the same JSON. The samples
below are executed by `packages/engine_core/test/doc_examples_ai_test.dart`.

## Behaviors are the leaves

A `Behavior` looks at the world and returns an `Action`; the trees and machines only decide
*which* behavior runs. Register behaviors by id:

```dart
final behaviors = BehaviorRegistry()
  ..register('see_player', SeePlayer())   // returns FailureAction when it can't
  ..register('chase', Chase())
  ..register('patrol', Patrol());
```

A leaf node succeeds unless its behavior returns a `FailureAction`, which makes it fail —
that is how a "can I see the player?" check is written.

## Behavior trees

```dart
final tree = {
  'type': 'selector', 'id': 'root',            // try children until one succeeds
  'children': [
    {
      'type': 'sequence', 'id': 'attack',      // run children until one fails
      'children': [
        {'type': 'leaf', 'id': 'look', 'behaviorId': 'see_player'},
        {'type': 'leaf', 'id': 'go', 'behaviorId': 'chase'},
      ],
    },
    {'type': 'leaf', 'id': 'walk', 'behaviorId': 'patrol'},
  ],
};

world.storeOf<AIState>().set(guard, AIState('tree', memory: {'_bt_root': tree}));
world.addSystem(BehaviorTreeSystem(behaviors));
```

Each step the system ticks the tree: `look` fails, so the sequence stops before `chase`, and
the selector falls through to `patrol`.

Node types (`type` in the JSON): `sequence`, `selector`, `parallel`, `randomSelector`,
`randomSequence`; decorators `inverter`, `succeeder`, `failer`, `repeater`, `untilSuccess`,
`untilFailure`, `timeout`, `throttle`, `cooldown`; leaves `leaf`, `wait`, `timer`.
Every node needs a unique `id`: a running node remembers its progress in the entity's
**blackboard** (`AIState.memory['_bt_blackboard']`) under that id. The same tree can
be built in Dart (`BTSequence(children: [...])`) and `toJson()`'d; the two forms are
interchangeable.

!!! warning "Give every node an id"
    A composite stores which child it was running as `<id>_runningIndex`. Two composites
    without ids (or with the same id) share a slot and will confuse each other.

## State machines

A machine has named states; each state runs a behavior tree (or a single behavior), and has
transitions to other states:

```json
{
  "id": "guard",
  "currentState": "patrol",
  "states": {
    "patrol": {
      "name": "patrol",
      "behaviorTree": { "type": "leaf", "id": "p", "behaviorId": "patrol" },
      "transitions": { "chase": { "toState": "chase", "condition": "player_visible" } }
    },
    "chase": {
      "name": "chase",
      "behaviorTree": { "type": "leaf", "id": "c", "behaviorId": "chase" },
      "transitions": { "patrol": { "toState": "patrol", "condition": "player_lost" } }
    }
  }
}
```

Conditions are code, so JSON holds only their **names**; the game binds each name to a
function when it installs the system:

```dart
world.addSystem(StateMachineSystem(behaviors, conditions: {
  'player_visible': (ctx) => canSee(ctx.view, ctx.entity),
  'player_lost': (ctx) => !canSee(ctx.view, ctx.entity),
}));
world.storeOf<AIState>().set(guard, AIState('fsm', memory: {'_fsm_root': json}));
```

Each step the system tries the current state's transitions in order (the first whose
condition is true wins), then ticks the (new) state. The current state is written back to
`currentState` in the JSON, so a transition persists — and saves/loads with the entity.

- A condition name with no bound function never fires, so a typo leaves the machine idle
  rather than crashing.
- A state can be a single `behaviorId` instead of a tree; it then runs every step.

## Not covered here yet

Steering (`steering.dart`), hearing and `InvestigateBehavior` (`hearing.dart`), pathfinding
and `FleeBehavior`; their source has doc comments, but there is no guide or executed
sample for them yet (tracked in `TODO.md`).
