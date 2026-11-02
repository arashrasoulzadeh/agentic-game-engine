# Writing games with less code

The shortest path from nothing to a running simulation, and the small set of
calls you will use every day. Everything here is plain `World` API underneath,
so you can always drop down to [the ECS](ecs.md) when you need to. The code on
this page is exercised by `packages/engine_core/test/doc_examples_authoring_test.dart`.

## One call to start

```dart
final game = GameBuilder.create(width: 320, height: 240, fixedStep: 1 / 60);
final ball = game.spawn([Position(10, 10), Velocity(60, 0)]);

game.update(1 / 60);          // call once per frame; returns the steps it ran
```

`GameBuilder.create` registers the core components, adds `SystemPresets.core`
(timers, optional AI, movement, collision, pushing, tile animation, tweens,
particles, in a verified order), seeds `world.random` and, with `fixedStep`,
simulates in whole steps whatever the frame rate. `game.pause()`, `resume()`
and `stop()` do what they say; `game.world` is the world.

## Components

```dart
final id = world.spawn();
world.setComponent(id, Position(1, 2));    // throws if the entity is dead
world.getComponent<Position>(id);          // Position? (null if absent)
world.hasComponent<Position>(id);
world.removeComponent<Position>(id);
world.componentsOf<Position>();            // the whole collection, for loops
```

`storeOf` is the old name of `componentsOf` and is deprecated.

## Creating entities

```dart
final a = world.spawnWith([Position(10, 20), Velocity(5, 0)]);
final b = world.spawnAt(3, 4);
final c = world.entity().at(10, 20).add(Collider(8)).build();   // an EntityRef

world.addTag(a, 'enemy');
world.withTag('enemy');                    // every entity tagged "enemy"
```

`spawnWith` is all-or-nothing: an unregistered component throws before any
entity exists. `build()` returns an `EntityRef`, a world-bound handle whose
operations check that the entity is still the same one (ids are recycled).

## Finding things

```dart
for (final (id, pos) in world.query<Position>()) { /* ... */ }
for (final (id, pos, vel) in world.query2<Position, Velocity>()) {
  pos.x += vel.x * dt;
}
```

Queries are lazy and read the component collections directly. Do not destroy
entities or add/remove the looped component inside the loop: the collection
reorders. In debug builds an assert tells you; the fix is the next section.

## Changing things while you loop

```dart
for (final (id, health) in world.query<Health>()) {
  if (health.current <= 0) world.commands.destroy(id);
}
// applied after the system finishes (and between systems)
```

`world.commands` queues `set`, `remove` and `destroy` (and an immediate
`spawn`). A queued change aimed at an entity that is gone by the time it runs
is skipped, even if the id was reused.

## Systems in a line

```dart
world.addSystemFn('spin', (world, dt) {
  for (final (_, r) in world.query<Rotation>()) {
    r.angle += dt;
  }
});

world.addSystem(SystemGroup('combat', [DamageSystem(), DeathSystem()]));
world.addSystemFn('hud', updateHud, phase: SystemPhase.late);
world.setSystemEnabled('combat', false);   // skipped, keeps its place
world.validateSystemOrder();               // [] when every after: holds
```

Phases run `prePhysics`, `physics` (the default), `postPhysics`, `late`; inside
a phase, registration order. `addSystem(system, after: ['movement'])` records a
dependency that `validateSystemOrder` checks. Nothing is reordered behind your
back.

## Time and randomness

```dart
world.after(2.0, () => spawnBoss());       // simulated seconds, not wall clock
final tick = world.every(0.5, spawnCoin);
tick.cancel();

world.random.nextInt(6);                   // seeded, repeatable, snapshot-able
final w = World(width: 800, height: 600, seed: 42);
```

`after`/`every` use closures, so they are not saved. For a timer that must
survive save/load, put a `CountdownTimer` component on an entity, add
`CountdownTimerSystem`, and listen for `CountdownTimerFired`.

## Saving, checking, inspecting

```dart
final data = world.save();                 // plain JSON, includes the random stream
world.load(data);                          // restores ids, components and tick

world.checkPatch(patch);                   // problems with paths, applies nothing
world.applyPatch(patch, strict: true);     // all or nothing
print(world.debug());                      // one-screen summary
```

## Testing your game

```dart
final t = GameTester(width: 100, height: 100, seed: 1);
final ball = t.world.spawnWith([Position(0, 0), Velocity(60, 0)]);
t.advance(1);                                  // one simulated second
expect(t.component<Position>(ball).x, closeTo(60, 1));
expectGolden('test/golden/ball.json', t.snapshotText());
```

`import 'package:engine_core/engine_core_testing.dart'`. `tickUntil` waits for a
condition and fails with `world.debug()` instead of hanging; `expectGolden`
creates a missing golden and, under `UPDATE_GOLDENS=1`, refreshes it.

## What agents can call and what stays code

The agent API is a set of operations (see the
[operations reference](../reference/operations.md)). The conveniences on this
page are mostly in-process sugar over the same registered components, so they
are deliberately not operations:

| Code API | Agent route |
|---|---|
| `spawnWith`, `entity()`, `spawnAt`, `EntityRef` | `level.add_entity` (files) or `world.build` (a sandbox world); same component JSON |
| `query`, `query2`, `query3` | `world.query` (by component name and field values) |
| tags, `CountdownTimer` | ordinary components: `level.set_field`, `world.patch` |
| `save` / `load` | `world.snapshot` reads a sandbox world; sandbox worlds are throwaway |
| `checkPatch`, strict `applyPatch` | `world.patch` with `dryRun` / `strict` |
| `commands`, events, systems, phases, `after`/`every`, `GameBuilder` | code that runs the game, not data an agent edits |
| `validateSystemOrder`, `debug()` | needs your game's code, so assert it in a test with `GameTester` (`engine_core_testing`); `game_agent project doctor` checks content and dependency wiring |
