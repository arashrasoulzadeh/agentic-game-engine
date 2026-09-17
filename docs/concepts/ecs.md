# The ECS: World, Entity, Component, System

`engine_core`'s simulation model, in `packages/engine_core/lib/src/ecs/`.

## Entity

An `EntityId` is just an id (see `packages/engine_core/lib/src/ecs/entity.dart`)
— an entity has no data or behavior of its own; it's only ever the key
components are stored under.

```dart
final id = world.spawn(); // EntityId
```

## Component

A component is plain data with `toJson`/`fromJson` — e.g. `Position`,
`Velocity`, `Collider` (`packages/engine_core/lib/src/physics/`). Each
component type lives in its own `ComponentStore<T>`, reachable via
`world.storeOf<T>()`:

```dart
world.storeOf<Position>().set(id, const Position(100, 100));
final pos = world.storeOf<Position>().get(id); // Position?
final has = world.storeOf<Position>().has(id); // bool
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
whichever entities it cares about (`packages/engine_core/lib/src/ecs/system.dart`):

```dart
abstract class System {
  void update(World world, double dt);
}
```

Add one with `world.addSystem(YourSystem())`. **Registration order
matters** — a system that reads state another system produces this
tick must run after it. `engine_platformer`'s `installPlatformerSystems`
exists specifically because getting this order right by hand is a real,
easy-to-get-wrong problem (see its own doc comment in
`packages/engine_platformer/lib/src/system_pack.dart` for the concrete
bug this caused once: jump consumption running before tile-based
grounding was resolved).

## World

`World` owns every `ComponentStore`, the system list, and the fixed-
timestep tick counter:

```dart
final world = World(width: 800, height: 600);
world.addSystem(MovementSystem());
final id = world.spawn();
world.storeOf<Position>().set(id, const Position(0, 0));
world.storeOf<Velocity>().set(id, const Velocity(50, 0));
```

`GameRunner` (in `engine_flutter`) creates one `World` per `Scene` and
drives its systems on a fixed timestep each frame — you don't call
`update` yourself in a normal Flutter game; you only add systems and
spawn entities in `Scene.populate`.

## Queries

For ad-hoc iteration outside a hand-written system loop (typically in a
`Behavior`, see [agent-api.md](agent-api.md)), `WorldView` provides
`entitiesWith<T>()` and `entitiesWithAll<A, B>()` — see
`packages/engine_core/lib/src/ecs/world_view.dart`.

## Events

`EventBus` (`packages/engine_core/lib/src/ecs/event_bus.dart`) is the
decoupling mechanism between systems that shouldn't directly call each
other — e.g. a collision system emitting a "damage" event a combat
system subscribes to, rather than the collision system importing and
calling combat logic directly. See `packages/engine_core/README.md`'s
"Events" section for the concrete API and `event_helpers.dart` for the
common-case wrappers.

## See also

- [content-as-data.md](content-as-data.md) — serializing/patching a `World` as JSON.
- [agent-api.md](agent-api.md) — the `Behavior`/`WorldView` sandbox for runtime agents.
- [`packages/engine_core/README.md`](../../packages/engine_core/README.md) — full API reference.
