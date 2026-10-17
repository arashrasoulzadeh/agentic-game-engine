# FAQ and troubleshooting

## Setup

### `game_agent: command not found`
`dart pub global activate` installs into the pub cache's `bin/`, which must be
on your `PATH` (usually `~/.pub-cache/bin`). The activate command prints the
exact line to add if it isn't.

### `flutter pub get` fails with "version solving failed" in a package of this repo
Inside the monorepo, packages reference each other through a *self-referencing
git dependency* plus a gitignore-safe `pubspec_overrides.yaml` that points at
local paths. If resolution fails with an authorization error from pub.dev,
you're offline or behind a mirror that doesn't allow a transitive package;
`flutter pub get --offline` works when the cache already has everything.
Never change those git dependencies to `path:` by hand — see
[CLAUDE.md](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/CLAUDE.md#non-obvious-constraints-dont-relitigate-these).

### "'Text' is defined in both … engine_flutter and flutter/material.dart"
`Text`, `Velocity` and `Action` collide with Flutter types by design. Hide one
side: `import 'package:flutter/material.dart' hide Text, Velocity, Action;`.

## ECS and data

### My component isn't saved or loaded
Only **registered** components appear in `World.toJson()` and are accepted by
`applyPatch` / `Level.loadInto`. Register yours:

```dart
world.components.register<Poison>('poison', (p) => p.toJson(), Poison.fromJson);
```

and for built-ins call the package's `register…Components(world)`.
A `StateError` from `storeOf<X>()` means `X` was never registered.

### `applyPatch` ignored my entity
It only updates entities that are **alive**; it never spawns. Spawn first
(see [save and restore](examples/save-restore-turn-game.md)).

### My system works alone but breaks with others
Order. Systems run in registration order; a system that reads what another
produces must come after it. Print `world.systemOrder`. Prefer the
`install…Systems` helpers, which encode the right order.

### An event handler never fires
Events are delivered at the **end of `World.step`**, not at `emit`. If you
call `emit` and check immediately, nothing has happened yet. Also handlers are
keyed by exact type — subscribe to the concrete event class.

## Turn-based strategy

### My units can't act on the first turn
`startTurnBasedGame` refills the first team's action points *when called*.
Spawn units **before** it. (Units spawned later start with 0 points.)

### `submitOrder` returns `false`
Not that unit's team's turn, the unit has no `Team`, there is no turn clock, or
the game is over (`TurnState.winner != null`). It never throws for these.

### My attack order disappears
An `OrderFailedEvent` was emitted — listen for it and read `reason`:
`invalidTarget` (dead, friendly, or **not visible through fog**), `blocked`
(no path), or `outOfRange` (only when approach is off).

### The AI team never moves
- Is its `TurnAI` registered under the exact team id in `aiTeams`?
- Can it see an enemy? `AggressiveAI` holds position when nothing is visible.
- Did you call `startTurnBasedGame`? `AITurnSystem` acts when the turn clock
  says it's that team's turn; with no clock nothing runs.
- Are you calling `world.step` after `endTurn`? The AI plans on one step and
  its orders execute on the next.

### The turn never ends for the AI
`AITurnSystem` ends the turn once no queued order can progress. If a custom
`TurnAI` keeps re-queuing orders every tick it stays "busy" — plan once per
`playTurn` call (the system calls it once per round).

### Units walk through each other / stack
Pass occupied-cell awareness: `OrderSystem.withNavigator` and
`installStrategySystems` already block on other units. A custom `nextStep`
must use the `occupied` callback it's given.

### Diagonal movement cuts a wall corner
It shouldn't: diagonals are refused when either neighbouring cell is wall
terrain. If you pass `diagonals: false`, only orthogonal steps are generated.

### Fog hides my own units' targets
Your unit needs `Vision`. A unit without it contributes no sight. Use
`spawnStrategyUnit(..., visionRange: 4)`.

### Selection bar is at the wrong place
The marker follows `Position`; `GridToWorldSystem(cellSize)` must use the same
`cellSize` as `GridTapController`. `installStrategySystems(cellSize: …)` passes
it for you.

## Platformer

### The player falls through the floor
Wrong system order, or no `TileMap` with `solidTileIds`. Use
`installPlatformerSystems` and check `registerPlatformerComponents(world)` ran.

### Physics feels different on different devices
Set `EngineView.fixedTimestepSeconds: 1 / 60` so every step has the same `dt`.

## Docs and project

### Where is the API reference?
[API reference](api-reference.md). Every public symbol has a doc comment
explaining *why*.

### How do I add a docs page?
See [Working on the docs](contributing-docs.md).

### Is this on pub.dev?
Not yet (pre-1.0). Generated projects depend on the git repo; see
[Getting started](getting-started.md#why-a-git-dependency).

### Can it do 3D / real-time strategy?
3D: no, by decision. RTS: the building blocks (orders, selection, navigation,
fog) are in place; the missing pieces are a lockstep fixed-step driver and
flow-field pathfinding — tracked in
[the roadmap](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/TODO.md#turn-based-strategy).
