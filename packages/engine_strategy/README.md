# engine_strategy

Turn-based strategy assembly on top of
[engine_core](../engine_core/README.md) and
[engine_flutter](../engine_flutter/README.md). The data and rules
(turn clock, orders, grid navigation, combat, fog of war, selection)
live in `engine_core/lib/src/turn/` because they are genre-general;
this package wires them together in the correct order, the way
`engine_platformer` does for platformers. Plan and status:
[TODO.md](../../TODO.md#turn-based-strategy).

## Quick start

```dart
final world = World(width: 384, height: 432);
registerCoreComponents(world);
registerFlutterComponents(world);

installStrategySystems(
  world,
  navigator: GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1),
  cellSize: 48,
);

spawnStrategyUnit(world, team: 'red', col: 1, row: 6, cellSize: 48);
spawnStrategyUnit(world, team: 'blue', col: 5, row: 1, cellSize: 48);
startTurnBasedGame(world, ['red', 'blue']); // after units exist

// In Scene.handleTap:
GridTapController(48).handleTap(world, worldPosition);
```

`installStrategySystems` options: `fog: true` (adds `VisionSystem` and a
`FogOfWar` entity), `blocksSight` (walls for line of sight),
`autoEndTeams` (teams whose turn ends when out of action points),
`aiTeams` (`{'blue': AggressiveAI()}` -- any `TurnAI` that calls
`submitOrder`),
`attackRange`/`attackCost`, `defendBonus`, `selectionMarkers`, and
`moveHighlight: (atlasId: 'terrain', region: 'highlight')` to light up the
selected unit's reachable cells (`MoveRangeHighlightSystem`).

## System order

`vision` (if fog) -> `orders` -> `aiTurn` (if AI) -> `turn` -> `winCondition` ->
`gridToWorld` -> `selectionMarkers` -> `moveRangeHighlight` (if enabled). Orders run after vision so attack
visibility checks are current; `gridToWorld` runs after orders so
rendering never lags a tick behind the grid.

## Agents

Everything is world state: `TurnState`, `ActionPoints`, `OrderQueue`,
`Selected`, `FogOfWar` serialize with `World.toJson()`. An agent acts
through `submitOrder(world, unit, MoveOrder(c, r) | AttackOrder(id))` --
the same path a tap uses -- and `canSee`/`FogOfWar` give it exactly the
visibility its team has.

Scaffold a starter with `game_agent create my_game --template strategy_game`.
