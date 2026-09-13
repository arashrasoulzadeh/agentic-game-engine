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
bounds), `CollisionSystem` (circle-vs-circle, emits `CollisionEvent`),
and `ParticleSystem` (spawns/ages `Particle` entities from
`ParticleEmitter`s — see below) are the only built-in systems here —
they're genre-general. Gravity,
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
| `ParticleEmitter(rate, burstCount, ...)` | Attach to an entity with a `Position`; `ParticleSystem` spawns `Particle` entities from it — `rate` for continuous emission, `burstCount` for a one-shot burst (consumed back to 0 the tick it fires) |
| `Particle(lifetime, startScale, endScale, startAlpha, endAlpha, colorArgb)` | One spawned particle; ages via `ParticleSystem`, destroyed once `age >= lifetime`. `scale`/`alpha` ramp linearly over the particle's life — `engine_flutter`'s `EngineView` reads them to render. `colorArgb` is a plain int (not a Flutter `Color`) so this stays Flutter-free |
| `Tween(from, to, duration, ...)` | Interpolates one `double`; advanced by `TweenSystem`, read via `.value` — see Tweening/easing below |

### Tweening/easing

```dart
world.addSystem(TweenSystem());

final shake = world.spawn();
world.storeOf<Tween>().set(shake, Tween(
  from: -4, to: 4, duration: 0.08,
  pingPong: true, easing: EasingType.easeInOutQuad,
));
```

`Tween` interpolates one `double` from `from` to `to` — it doesn't
write into any other component itself; read `.value` each tick and
apply it to whatever it's driving (a `Position.x` offset for a screen
shake, a UI opacity, a menu slide). `EasingType` is a plain enum
(`linear`, `easeInQuad`, `easeOutQuad`, `easeInOutQuad`) rather than a
closure, so `Tween` stays JSON-plain like everything else. `loop`
restarts from `from`; `pingPong` reverses direction at each end
instead (wins over `loop` if both are set). A plain (non-looping,
non-ping-pong) tween fires `TweenCompleteEvent` exactly once when it
finishes:

```dart
world.events.on<TweenCompleteEvent>((e) {
  if (e.entity == shake) world.destroy(shake);
});
```

### Particles

```dart
world.addSystem(ParticleSystem());
world.addSystem(MovementSystem()); // moves particles via their Velocity

final emitter = world.spawn();
world.storeOf<Position>().set(emitter, Position(100, 100));
world.storeOf<ParticleEmitter>().set(emitter, ParticleEmitter(burstCount: 20));
```

`ParticleSystem` spawns particles with `Position`/`Velocity` (a random
angle/speed within the emitter's configured range) and relies on
`MovementSystem` to actually move them — it doesn't duplicate velocity
integration. See `engine_flutter`'s README for how particles render.

### Events

```dart
world.events.on<CollisionEvent>((e) {
  // e.a, e.b — the two colliding entity ids
});
```

Typed pub/sub so systems don't call each other directly. Events queued
during `update()` are flushed once per `world.step()`, after all
systems have run.

**Collision convenience helpers** — `CollisionEvent.a`/`.b` are
unordered, so "did the player touch this coin" always means checking
both orderings; these extension methods on `World` do that for you:

```dart
world.onCollisionBetween(a, b, () { ... });                 // exactly this pair
world.onCollisionInvolving(player, (other) { ... });        // player + anything
world.onCollisionWithAny(coinIds, (coin, other) { ... });   // any coin + anything
```

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

Test coverage is 100% (line coverage via `package:coverage`):

```bash
dart pub global activate coverage
dart pub global run coverage:test_with_coverage
# coverage/lcov.info
```

## Benchmarks

`benchmark/` holds `package:benchmark_harness` micro-benchmarks for
this package's hot paths — a baseline for *future* performance work
(TODO.md tracks specific findings), not something every change needs
to re-run. Each file scales entity count over a few sizes so you can
see how a change affects scaling, not just absolute speed at one size:

```bash
dart run benchmark/world_step_benchmark.dart       # per-tick floor (MovementSystem only)
dart run benchmark/collision_system_benchmark.dart # CollisionSystem under crowding
dart run benchmark/particle_system_benchmark.dart  # steady-state particle emission/aging
dart run benchmark/entity_churn_benchmark.dart     # spawn/destroy throughput
```

`collision_system_benchmark.dart` already found a real scaling problem
worth fixing (see TODO.md's Performance section). `entity_churn_benchmark.dart`
is literally how a real bug in `ComponentStore.remove` was caught —
it crashed with a `RangeError` on its very first run, since churning
entities constantly hits the "just removed the last/only dense entry"
path unit tests hadn't happened to exercise. Already fixed, with a
regression test (`component_store_test.dart`) — worth remembering as a
case for keeping benchmarks around even when nothing is actively being
optimized: they're also just more code paths a fuzzing-adjacent stress
test walks that unit tests might not think to.
