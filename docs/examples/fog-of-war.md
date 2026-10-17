# Recipe: fog of war with walls

```dart
final walls = {(4, 3)};                                   // cells that block sight

final fogEntity = installStrategySystems(
  world,
  navigator: GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1),
  cellSize: 48,
  fog: true,
  blocksSight: (col, row) => walls.contains((col, row)),
)!;                                                       // returns the fog entity

final scout = spawnStrategyUnit(world,
    team: 'red', col: 2, row: 3, cellSize: 48, visionRange: 4);
final near  = spawnStrategyUnit(world, team: 'blue', col: 3, row: 3, cellSize: 48);
final spy   = spawnStrategyUnit(world, team: 'blue', col: 6, row: 3, cellSize: 48);
startTurnBasedGame(world, ['red', 'blue']);
world.step(1 / 60);                                       // VisionSystem runs
```

Now query it:

```dart
final fog = world.storeOf<FogOfWar>().get(fogEntity)!;

fog.isVisible('red', 3, 3);        // true  — inside the circle, clear line
fog.isVisible('red', 5, 3);        // false — behind the wall at (4, 3)
fog.isExplored('red', 3, 3);       // true  — once seen, always explored

canSee(world, 'red', near);        // true
canSee(world, 'red', spy);         // false — and AttackOrders on it fail
canSee(world, 'red', scout);       // true  — you always know your own units
```

## Drawing the fog

Loop the grid and shade by state:

| State | Test | Draw |
|---|---|---|
| Visible | `fog.isVisible(team, c, r)` | nothing |
| Explored, not visible | `fog.isExplored(team, c, r)` | dim overlay (remembered terrain) |
| Unknown | neither | opaque black |

Hide enemy sprites whose cell isn't visible — `canSee(world, localTeam, e)` is
the check to use, and it's already what attack orders and `AggressiveAI` use.

## Rules to remember

- **`visible` is recomputed every tick; `explored` only grows.**
- **Sight and walking are separate.** `blocksSight` is its own callback, so
  water can block movement but not vision (and a hedge can do the opposite).
- **The line's endpoints never block.** A unit adjacent to a wall sees the wall.
- **Own units are always visible to their team** regardless of fog.
- **Fog is optional.** With no `FogOfWar` in the world, `canSee` is always true.

*Verified by `doc_examples_test.dart` ("fog of war with walls").*
