# The ECS: World, Entity, Component, System

`zarvan_core`'s simulation model, in `packages/zarvan_core/lib/src/ecs/`.

## Entity

An `EntityId` is just an id (see `packages/zarvan_core/lib/src/ecs/entity.dart`)
— an entity has no data or behavior of its own; it's only ever the key
components are stored under.

```dart
final id = world.spawn(); // EntityId
```

## Component

A component is plain data with `toJson`/`fromJson` — e.g. `Position`,
`Velocity`, `Collider` (`packages/zarvan_core/lib/src/physics/`). Each
component type lives in its own `ComponentStore<T>`. Use the per-entity calls
for one entity and `world.componentsOf<T>()` when you loop over all of them:

```dart
world.setComponent(id, Position(100, 100));          // throws if the entity is dead
final pos = world.getComponent<Position>(id);        // Position?
final has = world.hasComponent<Position>(id);        // bool
final all = world.componentsOf<Position>();          // the whole collection
```

A component type must be **registered** before it participates in
`World.toJson()`/`applyPatch()`/`Level.loadInto()` — see
[content-as-data.md](content-as-data.md). Engine built-ins are
registered by `registerCoreComponents`/`registerFlutterComponents`/
`registerPlatformerComponents`; your own game-specific components are
registered the same way via `world.components.register<T>(id, toJson,
fromJson)`. An unregistered component silently can't be serialized —
this is a documented common mistake (see `CLAUDE.md`'s ECS section).

## System

A `System` is one unit of simulation logic that runs every tick over
whichever entities it cares about (`packages/zarvan_core/lib/src/ecs/system.dart`):

```dart
abstract class System {
  void update(World world, double dt);
}
```

Add one with `world.addSystem(YourSystem())`. **Registration order
matters** — a system that reads state another system produces this
tick must run after it. `zarvan_platformer`'s `installPlatformerSystems`
exists specifically because getting this order right by hand is a real,
easy-to-get-wrong problem (see its own doc comment in
`packages/zarvan_platformer/lib/src/system_pack.dart` for the concrete
bug this caused once: jump consumption running before tile-based
grounding was resolved).

## World

`World` owns every `ComponentStore`, the system list, and the fixed-
timestep tick counter:

```dart
final world = World(width: 800, height: 600);
registerCoreComponents(world); // Position, Velocity, ... (needed once per world)
world.addSystem(MovementSystem());
final id = world.spawn();
world.componentsOf<Position>().set(id, Position(0, 0));
world.componentsOf<Velocity>().set(id, Velocity(50, 0));
```

`GameRunner` (in `zarvan_flutter`) creates one `World` per `Scene` and
drives its systems on a fixed timestep each frame — you don't call
`update` yourself in a normal Flutter game; you only add systems and
spawn entities in `Scene.populate`.

## Queries

For ad-hoc iteration outside a hand-written system loop (typically in a
`Behavior`, see [agent-api.md](agent-api.md)), `WorldView` provides
`entitiesWith<T>()` and `entitiesWithAll<A, B>()` — see
`packages/zarvan_core/lib/src/ecs/world_view.dart`.

## Events

`EventBus` (`packages/zarvan_core/lib/src/ecs/event_bus.dart`) is the
decoupling mechanism between systems that shouldn't directly call each
other — e.g. a collision system emitting a "damage" event a combat
system subscribes to, rather than the collision system importing and
calling combat logic directly. See `packages/zarvan_core/README.md`'s
"Events" section for the concrete API and `event_helpers.dart` for the
common-case wrappers.

## See also

- [content-as-data.md](content-as-data.md) — serializing/patching a `World` as JSON.
- [agent-api.md](agent-api.md) — the `Behavior`/`WorldView` sandbox for runtime agents.
- [`packages/zarvan_core/README.md`](../../packages/zarvan_core/README.md) — full API reference.

## Time scale, hit-stop, pooling and spawners

**Time scale.** `world.timeScale` (1 normal, `0.25` slow motion, `0` pause) multiplies the `dt` every system and timer
receives. A system that must keep real time (UI, camera, input) adds `implements RealTimeSystem`. Events still flush
every step, so a paused world can react to input. `world.hitStop(0.07)` freezes simulated time for that many *real*
seconds, then resumes at the current scale: one call for a heavy blow. Neither is part of a save.

**Pooling.** `EntityPool(world)` recycles the component *objects* of short-lived entities (bullets, sparks):
`pool.acquire()` returns a `PooledEntity` whose `recycled` flag says whether it carries stale components from an earlier
use (set every field you rely on) or is brand new (build it as usual); `pool.release(id)` strips the entity into the
stash. The pool's `created` and `recycled` counters show whether it is working.

**Spawners.** A `Spawner` component on an entity with a `Position`, plus a `SpawnerSystem(prefabRegistry)`, spawns a
prefab on a schedule as pure data: `{"prefab": "coin", "every": 2, "delay": 1, "maxAlive": 5, "total": 20, "radius": 30}`,
or timed bursts with `"waves": [{"at": 5, "count": 3}]`. The first periodic spawn is at `delay`; `maxAlive` counts the
spawner's live spawns (each is tagged `SpawnedBy`) and a blocked spawner waits instead of banking a burst; `total`
retires it; spawns are deterministic for the world's seed. Each emits a `Spawned` event.
