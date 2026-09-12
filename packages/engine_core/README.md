# engine_core

Pure-Dart 2D game engine core: entities, components, systems, and the
agent-facing snapshot/content/behavior API. Zero Flutter dependency —
this package must build and run on the plain Dart VM, since it's used
by `engine_flutter` (which does target web) and could in principle be
tested or driven headlessly (CI, an agent's own tooling) without a
Flutter runtime at all.

## Install

```yaml
dependencies:
  engine_core:
    git:
      url: https://github.com/arashrasoulzadeh/agentic-game-engine.git
      path: packages/engine_core
      ref: main
```

(Normally you don't add this directly — `game_agent create` wires it up
for you. See [engine_cli](../engine_cli/README.md).)

## Core concepts

### World, entities, components

```dart
final world = World(width: 800, height: 480);
registerCoreComponents(world); // Position, Velocity, Collider, AIState, TileMap

final id = world.spawn();
world.storeOf<Position>().set(id, Position(100, 50));
world.storeOf<Velocity>().set(id, Velocity(0, 0));
```

Entities are plain integer ids. Components are plain data classes,
stored in a sparse-set `ComponentStore<T>` per type — `world.storeOf<T>()`
gets you the store for `T`, with `.get(id)`, `.set(id, value)`,
`.has(id)`, `.remove(id)`, and dense iteration (`.length`, `.entityAt(i)`,
`.denseAt(i)`) for systems that scan every instance of a component.

### Systems

```dart
class MyGravitySystem implements System {
  @override
  String get name => 'myGravity';

  @override
  void update(World world, double dt) { /* ... */ }
}

world.addSystem(MovementSystem());
world.addSystem(MyGravitySystem());
world.step(dt); // runs every registered system, in registration order
```

Systems run in the order they're registered — `world.systemOrder` lists
that order. This is deliberate: a bug is "read the list top to bottom,"
not "trace which system's `initState` ran first."

`MovementSystem` (integrates position by velocity, bounces off world
bounds) and `CollisionSystem` (circle-vs-circle, emits `CollisionEvent`)
are the only built-in systems here — they're genre-general. Gravity,
jump, and platform/tile *collision* logic (which needs `TileMap` data
but adds platformer-specific semantics like `grounded`) live in
[`engine_platformer`](../engine_platformer/README.md), including the
system-ordering rules for a platformer (`GravitySystem` →
`MovementSystem` → `PlatformerSystem`/`TileCollisionSystem` →
`JumpSystem` — order matters, see that package's README).

### Components reference

| Component | Purpose |
|---|---|
| `Position(x, y)` | World-space position |
| `Velocity(x, y)` | Per-second velocity, integrated by `MovementSystem` |
| `Collider(radius)` | Circle collider for entity-vs-entity collision |
| `TileMap(cols, rows, tileWidth, tileHeight, tiles, solidTileIds, oneWayTileIds)` | A tile grid for level geometry; attach to an entity with a `Position` (the grid's origin). The data type is genre-general (RPGs/puzzle games use tile grids too); only platformer *collision* against it lives in `engine_platformer` |
| `AIState(behaviorId, memory)` | Marks an entity as driven by a registered `Behavior` |

### Events

```dart
world.events.on<CollisionEvent>((e) {
  // e.a, e.b — the two colliding entity ids
});
```

Typed pub/sub so systems don't call each other directly. Events queued
during `update()` are flushed once per `world.step()`, after all
systems have run.

## The agent-facing API

This is the part that makes the engine "AI-agent-friendly," not just a
physics loop:

### 1. Content as data — `Level`

```dart
Level.loadInto(world, {
  'entities': [
    {'components': {'position': {'x': 10, 'y': 20}, 'collider': {'radius': 5}}},
  ],
});
```

Spawns entities from plain JSON via the same `ComponentRegistry` used
by `World.toJson()`/`applyPatch()`. `Level.validate(json)` checks the
shape and throws a specific `LevelLoadException` (e.g.
`entities[2].components["position"] must be an object`) rather than
silently accepting garbage — exposed as `game_agent lint <file>` in the
CLI.

### 2. Full state as JSON — `World.toJson()` / `applyPatch()`

```dart
final snapshot = world.toJson(); // {tick, width, height, entities: [...]}
```

Any component type registered via `world.components.register<T>(...)`
(as `registerCoreComponents`/`registerFlutterComponents` do for the
built-ins) is automatically included. `SaveGame` (in `engine_flutter`)
builds directly on this.

### 3. Runtime agents/NPCs — `WorldView` + `Behavior` + `AISystem`

```dart
class ChaseBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) {
    final pos = view.component<Position>(self);
    final target = view.nearestWithPosition(pos!.x, pos.y, exclude: self);
    if (target == null) return const NoOpAction();
    final t = view.component<Position>(target)!;
    return SetVelocityAction(self, t.x - pos.x, t.y - pos.y);
  }
}

final behaviors = BehaviorRegistry()..register('chase', ChaseBehavior());
world.addSystem(AISystem(behaviors));
world.storeOf<AIState>().set(enemyId, AIState('chase'));
```

A `Behavior` only ever sees a **read-only** `WorldView` — it cannot
mutate the world directly, only return an `Action` for `AISystem` to
apply. This is the sandbox: an LLM-backed or rule-based agent can
control an entity without any path to corrupting simulation state
outside what its own `Action` does.

Define your own `Action` subclasses for game-specific effects — see
`engine_platformer`'s `PatrolBehavior` for one that writes into the
entity's own `AIState.memory` blackboard through its `Action`.

## Testing

```bash
dart test
dart analyze --fatal-infos
```
