# Cheat sheet

One page of the calls you'll use most. Each section links to the full story.

## Worlds, entities, components

```dart
final world = World(width: 800, height: 600);
registerCoreComponents(world);                 // + registerFlutterComponents / registerPlatformerComponents
final e = world.spawn();
world.storeOf<Position>().set(e, Position(10, 20));
world.storeOf<Position>().get(e);              // Position? (null if absent)
world.storeOf<Position>().has(e);
world.destroy(e);
world.addSystem(MySystem());                   // order = registration order
world.step(1 / 60);                            // run all systems, flush events
world.systemOrder;                             // ['orders', 'turn', …]
world.toJson();  world.applyPatch(json);       // read / write everything
```

→ [ECS](../concepts/ecs.md) · [content as data](../concepts/content-as-data.md)

## Iterating a component store

```dart
final store = world.storeOf<Position>();
for (var i = 0; i < store.length; i++) {
  final entity = store.entityAt(i);
  final pos = store.denseAt(i);
}
```

## Events

```dart
world.events.on<UnitDamagedEvent>((e) => …);
world.events.emit(MyEvent());
```

→ [Events reference](events.md)

## Platformer in five lines

```dart
registerPlatformerComponents(world);
final player = spawnPlayer(world, x: 100, y: 100, input: input, maxHealth: 100);
spawnEnemy(world, x: 400, y: 400, behaviorId: 'patrol', maxHealth: 20);
installPlatformerSystems(world, player: player, behaviors: behaviors);
spawnHealthHudBar(world, source: player, x: 20, y: 20, width: 200, height: 20);
```

→ [Tutorial 1](../tutorials/01-hello-world.md) · [Platformer concepts](../concepts/platformer.md)

## Turn-based strategy in eight lines

```dart
final nav = GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1);
installStrategySystems(world, navigator: nav, cellSize: 48,
    aiTeams: {'blue': AggressiveAI()}, fog: false);
final u = spawnStrategyUnit(world, team: 'red', col: 1, row: 6, cellSize: 48);
startTurnBasedGame(world, ['red', 'blue']);       // after spawning
GridTapController(48).handleTap(world, worldPosition);   // in Scene.handleTap
submitOrder(world, u, MoveOrder(3, 4));           // or AttackOrder(enemyId)
endTurn(world);
```

→ [Tutorial 2](../tutorials/02-turn-based-strategy.md) · [Concepts](../concepts/turn-based-strategy.md)

## Turn-based quick reference

| I want to… | Call |
|---|---|
| Whose turn is it? | `turnStateOf(world)!.activeTeam` |
| Round number | `turnStateOf(world)!.round` |
| Who won? | `turnStateOf(world)!.winner` (null while playing) |
| Spend points | `trySpendActionPoints(world, unit, cost)` |
| Order a unit | `submitOrder(world, unit, MoveOrder(c, r))` |
| Cheapest path | `nav.findPath(from, to, blocked: …)` |
| Move-range cells | `nav.reachable(from, budget, blocked: …)` |
| Select / box-select | `selectAtCell` · `selectInBox` |
| Command the selection | `commandSelected(world, col, row)` |
| Can team see unit? | `canSee(world, team, entity)` |
| Chebyshev distance | `GridPosition.chebyshev(other)` |
| Run an AI turn | pass `aiTeams: {'blue': MyAI()}` |

## Default numbers

| Thing | Default |
|---|---|
| `spawnStrategyUnit` hp / attack / defense / action points | 10 / 3 / 0 / 3 |
| `OrderSystem` move cost / attack cost / attack range | 1 / 1 / 1 |
| `installCombat` damage | `max(1, attack − defense)` |
| Event cascade limit per flush | 20 rounds |
| `EngineView.fixedTimestepSeconds` | `null` (variable `dt`); typical opt-in value `1 / 60` |

## CLI

```bash
game_agent create my_game --template strategy_game
game_agent upgrade --ref main
game_agent lint assets/levels/main.level.json --playable
```

→ [CLI reference](cli.md)
