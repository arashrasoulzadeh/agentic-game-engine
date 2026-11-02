# Pickups, doors, patrols and waves

Four small recipes built only from core APIs. Each is exercised by
`packages/engine_core/test/doc_examples_pickups_test.dart`.

## Coin pickup

Tag the coins, ask what is near the player, and destroy through
`world.commands` so nothing is removed mid-loop.

```dart
final player = world.spawnAt(0, 0);
world.spawnWith([Position(3, 0), EntityTags(['coin'])]);
var coins = 0;
world.addSystemFn('pickup', (world, dt) {
  final p = world.getComponent<Position>(player)!;
  for (final id in world.findNear(p.x, p.y, 8, exclude: player)) {
    if (world.hasTag(id, 'coin')) {
      world.commands.destroy(id);
      coins++;
    }
  }
});
```

## Door and key

Pick-ups announce themselves with an event; the door listens.

```dart
world.on<KeyPicked>((_) {
  for (final id in world.withTag('door').toList()) {
    world.commands.destroy(id);
  }
});
world.events.emit(KeyPicked());
```

## Patrol

A function system that flips velocity at the bounds. `query2` joins the two
components; `SystemPresets.core` supplies movement.

```dart
world.addSystemFn('patrol', (world, dt) {
  for (final (_, pos, vel) in world.query2<Position, Velocity>()) {
    if (pos.x > 20 && vel.x > 0 || pos.x < 0 && vel.x < 0) vel.x = -vel.x;
  }
}, phase: SystemPhase.prePhysics);
SystemPresets.core(world);
```

## Enemy wave

`world.sequence` runs actions and waits on simulated time.

```dart
world.sequence([
  SeqStep.run(() => world.spawnAt(0, 0)),
  const SeqStep.wait(2),
  SeqStep.run(() => world.spawnAt(10, 0)),
]);
```
