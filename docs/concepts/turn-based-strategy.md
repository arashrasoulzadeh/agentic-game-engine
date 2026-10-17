# Turn-based strategy

How the strategy layer works: the data, the rules, and the order things
happen in. If you would rather build first and read later, jump to
[Tutorial 2](../tutorials/02-turn-based-strategy.md).

!!! info "Where the code lives"
    Data and rules: `packages/engine_core/lib/src/turn/` (pure Dart).
    Tap input and selection markers: `packages/engine_flutter`
    (`GridTapController`, `SelectionMarkerSystem`).
    One-call wiring: `packages/engine_strategy`
    (`installStrategySystems`, `spawnStrategyUnit`).

## The mental model

A strategy game here is **a grid, some teams, and a queue of orders**.

```mermaid
flowchart LR
    Input[Tap / UI / AI / external agent] -->|submitOrder| Q[OrderQueue<br/>per unit]
    Q --> OS[OrderSystem]
    OS -->|spends| AP[ActionPoints]
    OS -->|moves| GP[GridPosition]
    OS -->|attack| EV[AttackResolvedEvent]
    EV --> CB[installCombat]
    CB --> HP[UnitStats.hp]
    HP --> WC[WinConditionSystem]
    WC --> TS[TurnState.winner]
```

Everything that changes the game goes through the same two doors:
**`submitOrder`** (intent) and **`endTurn`** (pass). A human's tap, the
built-in AI and an LLM-backed agent are indistinguishable to the engine, so
none of them can do anything a player couldn't.

## Data

| Component | JSON | Purpose |
|---|---|---|
| `Team` | `{"id": "red"}` | Which side an entity is on. Plain string, so levels can invent teams. |
| `GridPosition` | `{"col": 3, "row": 5}` | Cell the unit stands in. The source of truth for rules. |
| `Position` | `{"x": 168, "y": 264}` | World pixels, **derived** from the grid by `GridToWorldSystem` for rendering. |
| `ActionPoints` | `{"current": 2, "max": 4}` | Budget for the active turn. |
| `UnitStats` | `{"hp": 8, "maxHp": 10, "attack": 3, "defense": 1}` | Combat numbers. |
| `AttackProfile` | `{"range": 3, "cost": 1}` | Per-unit attack reach and cost; absent = the global values. |
| `StatusEffects` | `{"effects":[{"id":"defending","turns":1,"attack":0,"defense":2}]}` | Temporary modifiers. |
| `Vision` | `{"range": 4}` | Sight radius in cells. |
| `OrderQueue` | `{"orders": [{"type":"move","col":3,"row":5}]}` | Pending orders. |
| `Objective` | `{"id":"hill","col":6,"row":6,"owner":null}` | A capture point. |
| `ObjectiveRules` | `{"holdTurnsToWin":3,"holds":{}}` | Optional hold-to-win rule. |
| `Selected` | `{}` | Marker: the local player has this unit selected. |
| `TurnState` | `{"order":["red","blue"],"activeIndex":0,"round":1,"eliminated":[],"winner":null}` | The turn clock. One per world. |
| `FogOfWar` | `{"cols":8,"rows":8,"visible":{…},"explored":{…}}` | Per-team visibility. One per world, optional. |

All of these are listed with types and limits in the
[component reference](../reference/components.md).

## The turn clock

```mermaid
stateDiagram-v2
    [*] --> RedTurn: startTurnBasedGame
    RedTurn --> BlueTurn: endTurn
    BlueTurn --> RedTurn: endTurn (round + 1)
    RedTurn --> Won: last blue unit dies
    BlueTurn --> Won: last red unit dies
    Won --> [*]
```

- `startTurnBasedGame(world, ['red', 'blue'])` creates the clock and **refills
  the first team's action points** — so spawn units first.
- `endTurn(world)` emits `TurnEndedEvent`, moves to the next team (skipping
  eliminated ones), increments `round` on wrap-around, refills that team's
  points and emits `TurnStartedEvent`.
- After a winner is set, `endTurn`, `submitOrder` and
  `trySpendActionPoints` all refuse.

### Action points

Every cost goes through one gate:

```dart
bool ok = trySpendActionPoints(world, unit, 2);
```

It fails — changing nothing — if it is not that unit's team's turn, the unit
has no `ActionPoints`, or it can't afford the cost. Because *everything*
spends this way, "can't act out of turn" is enforced in exactly one place.

## Orders

| Order | JSON | Behaviour |
|---|---|---|
| `MoveOrder(col, row)` | `{"type":"move","col":3,"row":5}` | Walks step by step, paying each cell's terrain cost. |
| `AttackOrder(target)` | `{"type":"attack","target":17}` | Walks into range if needed (with the navigator), then attacks. |
| `OverwatchOrder()` | `{"type":"overwatch"}` | Spends all remaining points and holds fire; shoots the first enemy that moves into the unit's attack range before its next turn, **interrupting that enemy's move where it stands**. Ends when it fires. |
| `DefendOrder()` | `{"type":"defend"}` | Spends all remaining points and applies `defending` (+2 defense by default) until the unit's next turn starts. With no points left it waits for the next turn. |

An order the unit **can't afford yet stays queued** and resumes next turn.
An order that **can never succeed** is dropped and an `OrderFailedEvent`
fires with a reason:

| `OrderFailure` | Meaning |
|---|---|
| `blocked` | No path (units or walls in the way). |
| `outOfRange` | Target too far (only without `approachTargets`). |
| `invalidTarget` | Target dead, friendly, missing, or hidden by fog. |

## Movement and terrain

`GridNavigator` is the rulebook for the grid:

```dart
final nav = GridNavigator(
  cols: 8, rows: 8,
  terrainCost: (col, row) => 1,   // return null for impassable
  diagonals: true,                // 8-way; never cuts a wall corner
);
nav.findPath(from, to);               // cheapest path, or null
nav.reachable(from, 4);               // every cell within 4 cost → for overlays
GridNavigator.fromTileMap(map, terrainCosts: {2: 3});   // forest = 3
```

- Diagonals cost the destination cell's cost.
- A diagonal is refused if either neighbouring cell is **wall terrain**, so
  units don't slip through corners. A *unit* beside the corner doesn't block
  it.
- Other units block the path (`blocked:` callback) but not diagonal corners.

## Combat

`installCombat(world)` listens for `AttackResolvedEvent` and applies

```
damage = max(1, attacker.attack − target.defense)
```

(never below 1, so fights can't deadlock on stats), then emits
`UnitDamagedEvent`, and on 0 hp `UnitDefeatedEvent` and destroys the unit.
There is **no friendly fire**: attack orders against your own team fail with
`invalidTarget`.

`WinConditionSystem` eliminates a team once it has no units left and sets
`TurnState.winner` when exactly one team remains (emitting `VictoryEvent`).
A team is only judged after it has been seen with units, so a unit-less
neutral side doesn't end the game on tick one.

### Ranged attacks and costs

Give a unit an `AttackProfile` to override the global range/cost:

```dart
spawnStrategyUnit(world, team: 'red', col: 0, row: 0, cellSize: 48,
    attackRange: 3);          // an archer: hits from 3 cells (Chebyshev)
spawnStrategyUnit(world, team: 'red', col: 1, row: 0, cellSize: 48,
    attackCost: 2);           // a mage: each spell costs 2 points
```

A unit that must approach stops as soon as it is within *its own* range.

### Status effects

`StatusEffects` hold temporary modifiers. Damage uses
`max(1, attack + Σ attack bonuses − (defense + Σ defense bonuses))`.

```dart
applyStatus(world, unit, StatusEffect('rally', turns: 2, attack: 3));
```

`turns` counts the **owner's** turn starts the effect survives: it is
decremented, and removed with a `StatusExpiredEvent`, at the start of the
owning team's turn. Re-applying an id refreshes it instead of stacking.

## Fog of war

Optional. `installStrategySystems(fog: true, blocksSight: …)` adds a
`FogOfWar` and `VisionSystem`.

- A cell is **visible** to a team if a unit's `Vision` circle reaches it and
  a Bresenham line to it crosses no `blocksSight` cell. The line's endpoints
  never block, so you can always see the wall you are looking at.
- `visible` is recomputed each tick; `explored` only grows.
- `blocksSight` is separate from terrain cost on purpose — you can see across
  a lake you can't walk over.
- `canSee(world, team, entity)` is true for your own units and for enemies on
  visible cells. **Attack orders on unseen enemies fail, and
  `AggressiveAI` obeys the same rule.**

## Objectives

Capture points turn "kill everything" into "hold the map".

```dart
final flag = world.spawn();
world.storeOf<Objective>().set(flag, Objective('hill', 6, 6));
// optional: win by holding every objective for 3 of your consecutive turns
world.storeOf<ObjectiveRules>().set(world.spawn(), ObjectiveRules(holdTurnsToWin: 3));
```

A team captures an objective by **standing on it when its turn begins** (resolved
synchronously by the turn clock, before any queued order can walk the unit away);
it stays theirs until someone else does the same. `ObjectiveCapturedEvent` fires
on every change of hands. With `ObjectiveRules`, owning *all* objectives at the
start of `holdTurnsToWin` consecutive own turns ends the game (`VictoryEvent`);
losing one resets the count.

`ObjectiveAI(navigator: nav)` plays for the map: garrisons hold owned points
(bracing, or fighting when an enemy gets close), nearby enemies are engaged, and
everyone else marches to the nearest objective the team doesn't own, spreading
out. With nothing left to take it hunts visible enemies.

### Escort and capture-the-flag

* **`Vip`** marks a unit whose death loses the game for its team no matter how many
  others are alive (`WinConditionSystem`, and `LastTeamStandingSystem` in real time).
* **`Flag`** is a carryable item. A unit of a *different* team that walks onto it
  picks it up (one per unit); it rides along; if the carrier dies it is **dropped
  where it fell** (`FlagDroppedEvent`) for anyone to take.
* **`DeliveryZone(team, col, row)`**: a carrier standing on its own team's zone
  scores a capture (`FlagCapturedEvent`) and the flag returns home. With
  `FlagRules(capturesToWin: 3)` the first team to that many wins.

```dart
world.storeOf<Vip>().set(king, const Vip());
world.storeOf<Flag>().set(world.spawn(), Flag('red flag', 'red', 10, 0));
world.storeOf<DeliveryZone>().set(world.spawn(), const DeliveryZone('blue', 0, 10));
world.storeOf<FlagRules>().set(world.spawn(), FlagRules(capturesToWin: 3));
```

Flags and zones carry their own `col`/`row` instead of a `GridPosition`, so they are
never mistaken for units: they don't block movement or appear in selection.
Pickup, carrying and delivery are resolved after every step either order system
takes, so it all works in real time too.

## Selection and input

Pure functions in the core:

| Function | Does |
|---|---|
| `selectAtCell(world, col, row, additive:)` | Select the active team's unit in a cell. |
| `selectInBox(world, c0, r0, c1, r1, additive:)` | Box select (corners in any order). |
| `commandSelected(world, col, row, replace:)` | Move to a free cell / attack an enemy there. |
| `clearSelection(world)` | Deselect all. |

and one Flutter helper that maps pixels to those calls:

```dart
final taps = GridTapController(48);          // cell size in pixels
taps.handleTap(world, worldPosition);        // → selected | commanded | ignored
taps.handleDrag(world, start, end);          // box select
```

## AI opponents

```dart
abstract class TurnAI { void playTurn(World world, String team); }
```

`AITurnSystem` runs a team's `TurnAI` **once at the start of its turn**,
lets `OrderSystem` execute what it queued, and ends the turn when no queued
order can still progress (the rest are waiting on points that arrive next
turn). `AggressiveAI` sends every idle unit after the nearest enemy its team
can see. `TacticalAI` adds four switchable behaviours — focus fire on the
weakest visible enemy, retreat when hurt, explore unexplored fog, and brace
when idle:

```dart
aiTeams: {'blue': TacticalAI(navigator: nav, retreatBelow: 0.3, defendWhenIdle: true)}
```

Writing your own is a ten-line class — [recipe](../examples/custom-turn-ai.md).

## System order

`installStrategySystems` registers, in this order:

| # | System | Why here |
|---|---|---|
| 1 | `vision` *(fog only)* | Visibility must be current before attacks are checked. |
| 2 | `orders` | Executes queued orders, spending points. |
| 3 | `aiTurn` *(AI only)* | After orders, so "nothing left affordable" sees this tick's results. |
| 4 | `turn` | Auto-ends teams listed in `autoEndTeams`. |
| 5 | `winCondition` | Judges eliminations after this tick's kills. |
| 6 | `gridToWorld` | Syncs pixels from the final cells. |
| 7 | `selectionMarkers` | Follows the synced pixels. |

Reordering these changes behaviour; add your own systems around them rather
than between.

## Events

| Event | Fired when |
|---|---|
| `TurnStartedEvent(team, round)` | A team's turn begins, points refilled. |
| `TurnEndedEvent(team, round)` | A team's turn ends. |
| `MovedEvent(entity, col, row)` | A unit enters a cell (one per step). |
| `AttackResolvedEvent(attacker, target)` | An attack lands (before damage). |
| `UnitDamagedEvent(attacker, target, amount)` | Damage applied. |
| `UnitDefeatedEvent(unit, team)` | A unit reaches 0 hp, just before destruction. |
| `OrderFailedEvent(entity, order, reason)` | An order was dropped. |
| `OverwatchTriggeredEvent(watcher, target)` | An overwatching unit fired. |
| `ObjectiveCapturedEvent(objective, team, previousOwner)` | A capture point changed hands. |
| `FlagPickedUpEvent(flag, carrier)` / `FlagDroppedEvent(flag, formerCarrier)` | A flag was taken / its carrier died. |
| `FlagCapturedEvent(flag, team, total)` | A flag was delivered; `total` is the team's captures. |
| `StatusAppliedEvent(entity, id)` | A status was applied or refreshed. |
| `StatusExpiredEvent(entity, id)` | A status ran out at its owner's turn start. |
| `VictoryEvent(team)` | One team remains. |

## Design decisions

- **Teams are strings**, not an enum — levels and agents can add sides without
  an engine change.
- **The grid is the truth, pixels are derived.** Mixing the two invites
  off-by-half-a-cell bugs.
- **Points refill at turn *start*,** so the budget an agent reads during the
  opponent's turn is the one it will really have.
- **`UnitStats`, not `Health`.** The platformer's `Health` lives later in the
  dependency chain, which a strategy package can't depend on.
- **No wall-clock time anywhere in the rules.** A game is a function of its
  orders, so it replays and tests deterministically.

## Not built yet

AI that carries and escorts (the rules exist; `ObjectiveAI` doesn't play
them yet). Looking for real time? See [Real-time strategy](realtime-strategy.md).
See [the roadmap](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/TODO.md#turn-based-strategy).
