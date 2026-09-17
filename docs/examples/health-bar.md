# Recipe: add a health bar

```dart
final player = spawnPlayer(world, x: 0, y: 0, input: input, maxHealth: 100);

spawnHealthHudBar(
  world,
  source: player,
  x: 20, y: 20,          // screen-space pixels (screenSpace defaults true)
  width: 200, height: 20,
  fillColorArgb: 0xFFE0304C,
  backgroundColorArgb: 0x80000000,
);
```

Syncing `value`/`maxValue` from `player`'s `Health` every tick is
handled by `HealthHudSystem` — already included if you called
`installPlatformerSystems(world, ...)`. If you're not using that helper,
add it yourself: `world.addSystem(HealthHudSystem())`.

## Floating over an enemy instead of pinned to the screen

```dart
final enemyBar = spawnHealthHudBar(
  world,
  source: enemy,
  x: enemy_x, y: enemy_y - 20, // world-space units now
  width: 40, height: 6,
  screenSpace: false,
);

// screenSpace: false means Position isn't auto-followed — update it
// yourself each tick (e.g. in a small custom System) to track the enemy:
world.storeOf<Position>().set(
  enemyBar,
  Position(world.storeOf<Position>().get(enemy)!.x, world.storeOf<Position>().get(enemy)!.y - 20),
);
```

See `HudBar.screenSpace`'s doc comment
(`packages/engine_flutter/lib/src/rendering/hud_bar.dart`) for the full
explanation of why world-space bars aren't auto-followed.
