// GENERATED — do not edit.
// dart run tool/gen_bundled_docs.dart

/// Curated markdown bodies for [kRemoteDocsPages] (engine.docs offline).
const kBundledDocs = <String, String>{
  'getting-started.md': '''# Getting started

From nothing to a running game in about five minutes.

```mermaid
flowchart LR
    A[Install CLI] --> B[game_agent create] --> C[flutter run] --> D[Edit data / Dart]
    D --> E[MCP / CLI ops: lint · validate · simulate]
```

## Prerequisites

| Need | Version | Check |
|---|---|---|
| Flutter SDK (includes Dart) | Dart `^3.9.0` | `flutter --version` |
| Git | any recent | `git --version` |

Git matters because projects depend on the engine through a git dependency,
not pub.dev ([why](#why-a-git-dependency)).

## 1. Install the CLI

```bash
dart pub global activate --source git \\
  https://github.com/arashrasoulzadeh/agentic-game-engine.git \\
  --git-path packages/engine_cli
```

`game_agent` is now on your `PATH` (add `~/.pub-cache/bin` if the command
prints a warning).

## 2. Pick a starter and create it

=== "Platformer"

    ```bash
    game_agent create my_game
    ```

    A player, solid ground, patrol enemy, coin, health bar, keyboard and
    on-screen controls. Continue with [Tutorial 1](tutorials/01-hello-world.md).

=== "Turn-based strategy"

    ```bash
    game_agent create my_war --template strategy_game
    ```

    An 8×8 skirmish against an AI; map and units in
    `assets/levels/skirmish.level.json` (editable via `level.*` /
    `strategy.simulate_turns`). Continue with
    [Tutorial 2](tutorials/02-turn-based-strategy.md).

=== "Idle / incremental"

    ```bash
    game_agent create bakery --template idle_game
    ```

    Generators, upgrades, prestige, challenges, golden offers and offline
    catch-up — the economy is one JSON file. Continue with
    [Tutorial 5](tutorials/05-idle-game.md).

Then:

```bash
cd my_game          # or my_war / bakery
flutter run         # pick a device, or: flutter run -d chrome
```

## 3. What you got

```text
my_game/
├── lib/main.dart            Game subclass, first Scene, runGame()
├── assets/
│   ├── game_config.json     world size, orientation, background colour
│   └── levels/main.level.json   (platformer) the starting level, as data
├── test/widget_test.dart    boots the game and finds the EngineView
└── pubspec.yaml             engine packages as git dependencies
```

### The shape of `main.dart`

```dart
class MyGame extends Game {
  @override
  GameConfig get config => _config;            // loaded from game_config.json

  @override
  Scene createInitialScene() => MainScene();
}

class MainScene extends Scene {
  @override
  Future<void> populate(
    World world, SceneController scenes, GameState state,
  ) async {
    // Core + Flutter components are already registered by GameRunner.
    world.addSystem(MovementSystem());
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(100, 100));
    world.storeOf<Velocity>().set(player, Velocity(0, 0));
  }
}

void main() => runGame(MyGame());
```

| Piece | Role |
|---|---|
| `Game` | App-level config, input controller, first scene. |
| `Scene` | One screen. Owns a fresh `World`; `populate` fills it, `loadAssets` loads sprites, `handleTap` receives taps. |
| `GameState` | Survives scene switches (score, unlocks). |
| `runGame` | Starts the Flutter shell. |

New to `World`, `spawn` and `storeOf`? Read the [ECS guide](concepts/ecs.md).

## 4. Keep going

| Next | Why |
|---|---|
| [Tutorials](tutorials/README.md) | Build a platformer, a strategy game, or an agent-driven game. |
| [Tutorial 6 · Agent API](tutorials/06-agent-api.md) | MCP / REST / CLI: create → open → edit → validate → undo. |
| [Operations reference](reference/operations.md) | Every op (same on MCP, REST, JSON-RPC, CLI). |
| [Cheat sheet](reference/cheatsheet.md) | The calls you\'ll use most, on one page. |
| [FAQ](faq.md) | If something doesn\'t work. |

## Everyday commands

```bash
game_agent upgrade --ref main                     # move the engine pin forward
game_agent lint assets/levels/main.level.json     # validate a level (add --playable)
game_agent idle validate assets/idle_game.json    # idle definition check
game_agent strategy simulate-turns assets/levels/skirmish.level.json --turns 4
game_agent project open .                         # then project.problems / level.* / idle.*
game_agent pack-assets --input art --output-image assets/packed/atlas.png
```

See the [CLI reference](reference/cli.md) and [transports](reference/transports.md) for MCP/REST.

Published docs (when `engine.docs` has no local `docs/`):
<https://meetarash.ir/agentic-game-engine/> (`engine.capabilities` → `docsUrl`).

## Why a git dependency?

The packages aren\'t on pub.dev yet (pre-1.0). A generated project depends on
`engine_core`, `engine_flutter` and the genre package (`engine_platformer` or
`engine_strategy`) through a **self-referencing git dependency** — same repo
URL and `ref` for each — rather than local `path:` entries. Pub treats a
resolved commit and a consumer\'s `ref: main` as different descriptions of the
same package and refuses to solve if they\'re mixed; the self-referencing form
avoids that. Don\'t hand-edit these to `path:`; use `game_agent upgrade`.
Details: the "Non-obvious constraints" section of
[CLAUDE.md](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/CLAUDE.md).

## Working on the engine itself

```bash
git clone https://github.com/arashrasoulzadeh/agentic-game-engine.git
cd agentic-game-engine
(cd packages/engine_core && dart test)
(cd packages/engine_flutter && flutter test)
```

See [CONTRIBUTING](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/CONTRIBUTING.md).
''',

  'tutorials/01-hello-world.md': '''# Tutorial: a tiny platformer

Builds up a minimal but real game — a player, solid ground, one patrol
enemy, one collectible, a health bar — using only public API. Follow
[getting-started.md](../getting-started.md) first to scaffold and run
`my_game`; this tutorial edits `lib/main.dart`.

Every snippet below is checked against current signatures in
`packages/engine_core/lib/src/` and `packages/engine_platformer/lib/src/`.

## Step 1 — a `Game` and a `Scene`

```dart
import \'package:engine_core/engine_core.dart\';
import \'package:engine_flutter/engine_flutter.dart\' hide Text;
import \'package:engine_platformer/engine_platformer.dart\';

class MyGame extends Game {
  final input = InputController();
  // InputController() with no args uses InputController.defaultBindings():
  // arrow keys -> left/right/up/down, space -> jump. Pass a custom
  // Map<LogicalKeyboardKey, String> to `bindings:` for different keys.

  @override
  GameConfig get config => const GameConfig(worldWidth: 800, worldHeight: 480);

  @override
  InputController? createInputController() => input;

  @override
  Scene createInitialScene() => MainScene(input);
}

void main() => runGame(MyGame());
```

The `InputController` is created once by `Game` and handed to the
`Scene` explicitly — `Scene.populate` doesn\'t receive it implicitly,
so pass `input.state` (an `InputState`) into your `Scene`\'s
constructor, the same pattern `spawnPlayer` expects (`input:` takes an
`InputState`, not the `InputController` itself).

## Step 2 — register platformer components and spawn the player

```dart
class MainScene extends Scene {
  MainScene(this.input);
  final InputController input;
  late final EntityId player;
  final behaviors = BehaviorRegistry();

  @override
  Future<void> populate(
    World world, SceneController scenes, GameState state,
  ) async {
    registerPlatformerComponents(world);

    player = spawnPlayer(
      world,
      x: 100, y: 100,
      input: input.state,
      jumpSpeed: 480,
      maxHealth: 100,
    );

    installPlatformerSystems(world, player: player, behaviors: behaviors);
  }
}
```

`spawnPlayer` attaches `Position`/`Velocity`/`Collider`/`Gravity`/
`PlatformerController` and, because `maxHealth: 100` was passed, also
`Health` + a `LastCheckpoint` at the spawn point. `installPlatformerSystems`
wires gravity, jump, collision, input, animation, health-tick, and
attack systems in the one order that\'s actually correct — see
[concepts/platformer.md](../concepts/platformer.md) for why this
matters.

## Step 3 — solid ground: a `TileMap`

```dart
final tileMap = TileMap(
  tileWidth: 32, tileHeight: 32,
  cols: 25, rows: 15,
  tiles: List.generate(25 * 15, (i) => i >= 25 * 13 ? 1 : 0), // tile id 1 fills the bottom two rows
  solidTileIds: {1}, // tile id 1 is solid; 0 is empty/passable
);
final groundEntity = world.spawn();
world.storeOf<TileMap>().set(groundEntity, tileMap);
```

`TileMap` also supports `oneWayTileIds` (platforms you can jump up
through), `slopeUpLeftTileIds`/`slopeUpRightTileIds` (ramps), and
ladder/conveyor/friction tile sets — see
`packages/engine_core/README.md`\'s `TileMap` section before authoring a
real level; the sketch above only uses the minimum for one solid floor.

## Step 4 — one patrol enemy

```dart
behaviors.register(\'patrol\', PatrolBehavior(minX: 300, maxX: 500, speed: 60));

final enemy = spawnEnemy(
  world,
  x: 400, y: 400,
  behaviorId: \'patrol\',
  affectedByGravity: true,
  maxHealth: 20,
);
```

`spawnEnemy` attaches `AIState(\'patrol\')`, so `AISystem` (already
wired by `installPlatformerSystems` since `behaviors` was passed)
drives it via the registered `PatrolBehavior` every tick — see
[concepts/agent-api.md](../concepts/agent-api.md) for how that decision
loop works.

## Step 5 — a health bar

```dart
spawnHealthHudBar(world, source: player, x: 20, y: 20, width: 200, height: 20);
```

`HealthHudSystem` (already included in `installPlatformerSystems`)
keeps this bar\'s `HudBar.value`/`maxValue` synced from the player\'s
`Health` every tick — nothing else to wire up.

## Step 6 — one collectible

```dart
final coinId = world.spawn();
world.storeOf<Position>().set(coinId, Position(450, 380));
world.storeOf<Collider>().set(coinId, Collider(8));
world.storeOf<Sprite>().set(coinId, Sprite(\'items\', \'coin\')); // if you have an atlas loaded

world.storeOf<Inventory>().set(player, Inventory({\'coin\': 0}));
dealPickupOnTouch(world, {coinId}, \'coin\');
```

`dealPickupOnTouch` wires a collision listener that calls
`collectItem` (adds to the player\'s `Inventory`, emits
`ItemCollectedEvent`) and destroys the coin entity by default.

## Step 7 — combat (optional)

Give the enemy a `Weapon` or let the player attack it — see
[concepts/platformer.md](../concepts/platformer.md)\'s Combat section
and `packages/engine_platformer/README.md` for `Weapon`/`AttackSystem`
setup; it\'s deliberately left out of this base tutorial to keep it
focused, but every helper it needs (`damageEntity`,
`installProjectileDamage`) is already covered there.

## Run it

```bash
flutter run
```

You should see a player that falls onto solid ground, can move/jump
with the bound keys, an enemy pacing between x=300 and x=500, a health
bar in the top-left, and a coin that disappears (and increments
`Inventory`) on contact.

## Next

- [examples/](../examples/README.md) — smaller focused recipes (save/load, custom Behavior, more).
- [concepts/](../concepts/architecture.md) — the underlying model for everything used above.
''',

  'tutorials/02-turn-based-strategy.md': '''# Tutorial 2: a turn-based strategy skirmish

**You will build:** an 8×8 battlefield where you command two red units
against a computer-controlled blue army, with terrain that slows movement,
fog of war, and a victory message.

**Time:** about 30 minutes. **Prerequisite:** [Getting started](../getting-started.md).
Background reading, if you want it:
[Turn-based strategy concepts](../concepts/turn-based-strategy.md).

!!! tip "Skip the typing"
    `game_agent create my_war --template strategy_game` generates the skirmish
    already assembled: map and units in `assets/levels/skirmish.level.json`
    (edit with `level.*` or `strategy.simulate_turns`), systems and AI in
    `lib/main.dart`. This tutorial shows the same pieces so you can change them.

Every code block below is executed by
`packages/engine_strategy/test/doc_examples_test.dart`, so what you read is
what runs.

## What you are making

```mermaid
flowchart LR
    You[You tap] -->|select + order| R[Red units]
    R -->|attack| B[Blue units]
    AI[AggressiveAI] -->|same submitOrder API| B
    B -->|attack| R
```

## Step 1 — a world and a grid

The *grid* is a `GridNavigator`: how big the board is and what it costs to
enter each cell. Start with every cell costing 1.

```dart
final world = World(width: 384, height: 384);
registerCoreComponents(world);
registerFlutterComponents(world);   // GameRunner does both for you inside a Scene

const cell = 48.0;                  // pixels per grid cell
final nav = GridNavigator(cols: 8, rows: 8, terrainCost: (col, row) => 1);
```

`terrainCost` returns the action points needed to *enter* a cell, or `null`
for a wall.

## Step 2 — install the systems

```dart
installStrategySystems(world, navigator: nav, cellSize: cell);
```

One call registers orders, turn handling, win detection, grid-to-pixel sync,
selection markers and combat, **in the order that works**. Printing
`world.systemOrder` shows
`[orders, turn, winCondition, gridToWorld, selectionMarkers]`.

## Step 3 — spawn two armies

```dart
final knight = spawnStrategyUnit(world,
    team: \'red\', col: 1, row: 6, cellSize: cell,
    maxHp: 12, attack: 5, actionPoints: 4);
final archer = spawnStrategyUnit(world,
    team: \'red\', col: 2, row: 6, cellSize: cell,
    attack: 3, actionPoints: 3);
final goblin = spawnStrategyUnit(world,
    team: \'blue\', col: 5, row: 2, cellSize: cell,
    maxHp: 8, attack: 2);
```

`spawnStrategyUnit` attaches `Team`, `GridPosition`, `Position`,
`ActionPoints`, `UnitStats` (and `Vision` / `Sprite` if you pass
`visionRange` / `atlasId` + `spriteRegion`). Defaults: 10 hp, 3 attack,
0 defense, 3 action points.

| Unit | Team | Cell | HP | Attack | Points |
|---|---|---|---|---|---|
| knight | red | (1, 6) | 12 | 5 | 4 |
| archer | red | (2, 6) | 10 | 3 | 3 |
| goblin | blue | (5, 2) | 8 | 2 | 3 |

## Step 4 — start the clock

```dart
startTurnBasedGame(world, [\'red\', \'blue\']);
```

!!! warning "Spawn first, then start"
    Starting the clock refills the first team\'s action points. A unit spawned
    afterwards begins with 0 points and can\'t act until its team\'s next turn.

Red moves first. `turnStateOf(world)!.activeTeam` is `\'red\'` and the knight
has 4 points.

## Step 5 — taps become orders

`GridTapController` turns a world-space tap into the right call:

```dart
final taps = GridTapController(cell);

taps.handleTap(world, const Offset(1.5 * cell, 6.5 * cell)); // tap the knight → selected
taps.handleTap(world, const Offset(1.5 * cell, 4.5 * cell)); // tap an empty cell → move order
world.step(1 / 60);                                          // the order executes
```

The knight walks two cells north, paying 1 point per cell, so it has 2 left.

Tapping an **enemy** issues an attack. The unit first walks into range:

```dart
taps.handleTap(world, const Offset(5.5 * cell, 2.5 * cell)); // tap the goblin
```

In a real game, put this in your scene:

```dart
@override
void handleTap(World world, SceneController scenes, Offset worldPosition) {
  taps.handleTap(world, worldPosition);
}
```

and give the player a way to pass the turn — the template uses a strip below
the grid:

```dart
if (worldPosition.dy >= 8 * cell) endTurn(world);
```

## Step 6 — terrain

Make some cells slow and some impassable using a `TileMap`:

```dart
const forest = 2, mountain = 3;
final map = TileMap(
  cols: 5, rows: 1, tileWidth: 48, tileHeight: 48,
  tiles: [0, forest, forest, mountain, 0],
  solidTileIds: {mountain},
);
final nav = GridNavigator.fromTileMap(map, terrainCosts: {forest: 3});
```

| Tile | Cost |
|---|---|
| `0` grass | 1 |
| `2` forest | 3 |
| `3` mountain | impassable |

Show the player where a unit can go with `reachable`:

```dart
final reach = nav.reachable(GridPosition(0, 0), 4);   // Map<(col,row), cost>
reach[(1, 0)];                                        // 3 — one forest cell
reach.containsKey((2, 0));                            // false — 3 + 3 > 4
```

Draw those cells as translucent rectangles: see
[Move-range overlay](../examples/move-range-overlay.md).

## Step 7 — an opponent

Pass a `TurnAI` for each computer-controlled team:

```dart
installStrategySystems(
  world,
  navigator: nav,
  cellSize: cell,
  aiTeams: {\'blue\': AggressiveAI()},
);
```

When blue\'s turn starts, `AggressiveAI` orders every unit that has action
points to attack the nearest enemy blue can see. The engine executes the
orders, then ends the turn by itself once nothing queued is affordable.

## Step 8 — react to what happens

Events are how your UI, sounds and score keep up. Subscribe once:

```dart
final log = <String>[];
world.events.on<UnitDamagedEvent>((e) => log.add(\'hit \${e.target} for \${e.amount}\'));
world.events.on<VictoryEvent>((e) => log.add(\'\${e.team} wins\'));
```

| Event | Use it for |
|---|---|
| `TurnStartedEvent` | "Your move" banner, clearing selection |
| `MovedEvent` | Footstep sounds |
| `UnitDamagedEvent` | Damage numbers, hit flash |
| `UnitDefeatedEvent` | Death animation |
| `VictoryEvent` | End screen |

## Step 9 — play a whole game headlessly

Because rules don\'t depend on Flutter, you can run the entire game in a test
or a script. Here red\'s hero attacks every round and blue\'s AI answers:

```dart
for (var round = 0; round < 10 && turnStateOf(world)!.winner == null; round++) {
  submitOrder(world, hero, AttackOrder(orc));
  world.step(1 / 60);                       // orders execute
  endTurn(world);
  for (var i = 0; i < 4; i++) {
    world.step(1 / 60);                     // AI plans, acts, hands the turn back
  }
}
// turnStateOf(world)!.winner == \'red\'
```

## Step 10 — fog of war

```dart
final walls = {(4, 3)};
installStrategySystems(
  world,
  navigator: nav,
  cellSize: cell,
  fog: true,
  blocksSight: (col, row) => walls.contains((col, row)),
);
spawnStrategyUnit(world, team: \'red\', col: 2, row: 3, cellSize: cell, visionRange: 4);
```

Now enemies behind the wall at (4, 3) are invisible to red, and so are
attacks against them. See the [fog recipe](../examples/fog-of-war.md).

## Checkpoint: what you should see

- Tapping a red unit shows a cyan bar under it.
- Tapping a free cell moves it, spending one point per step.
- Tapping a blue unit walks over and hits it for `attack − defense`.
- Passing the turn makes blue move toward you and attack.
- The last unit of a team dying shows the victory message and freezes input.

## Where to go next

- Write your own opponent: [Custom TurnAI](../examples/custom-turn-ai.md).
- Let an LLM or script play: [Tutorial 3](03-agent-driven-game.md).
- Persist a game: [Save and restore](../examples/save-restore-turn-game.md).
- Everything in one place: [Cheat sheet](../reference/cheatsheet.md).
''',

  'tutorials/05-idle-game.md': '''# 5 · An idle game in an afternoon

You will generate a cookie-clicker-style game, change its economy by editing one JSON file, check the pacing
without playing, and wire in the player-facing extras. No Dart is needed until you opt into automation.

## 1. Generate it

![The finished game](../img/idle-game.png)

```bash
game_agent create bakery --template idle_game
cd bakery
flutter run
```

You get a tap button, generators and upgrades, resource header, golden offers, prestige, challenges,
achievements, a stats card, durable saving (files on mobile/desktop, `localStorage` on web), and a
"while you were away" summary on both cold start and resume. The whole game is `assets/idle_game.json`.

## 2. Change the economy

Open `assets/idle_game.json`. Each generator has a price curve (`base` × `growth`^owned) and an output per
second. Add a new one after `mine`, and reward owning many of them with a milestone:

```json
{ "id": "factory", "name": "Factory",
  "cost": { "type": "geometric", "base": "130000", "growth": 1.15 },
  "output": { "coins": "260" },
  "milestones": [ { "owned": 25, "multiplier": "2" }, { "owned": 50, "multiplier": "2" } ] }
```

Prices can also be a hand-written table for the first few copies:
`{ "type": "table", "prices": ["10", "25", "60"], "tailGrowth": 1.2 }`.

Validate without launching the app:

```bash
game_agent idle validate assets/idle_game.json
```

Mistakes are reported with the path to them (`generators[4].cost.growth must be a number >= 1`).

## 3. Check the pacing without playing

```bash
game_agent idle simulate assets/idle_game.json --days 2 --prestige-at 2
```

It prints when income passes each power of ten, when it prestiges or clears challenges, and whether the design
stalls. The same simulator is pinned as a golden in the engine\'s tests, so any change in pacing becomes a
visible diff.

## 4. Extras already in the template

- **Offline earnings:** `"offline": { "capHours": 8, "efficiency": 0.5 }` — `OfflineSummaryDialog` on return,
  with an `onDouble` stub for a rewarded-ad 2× (`IdleSession.doubleOffline`).
- **Prestige layers and achievements:** Progress tab (one `PrestigePanel` per layer, `AchievementList`).
- **Challenges:** `"challenges"` in the JSON + `ChallengePanel` on Progress.
- **Auto-buyer:** `"autoBuyer"` + `AutoBuySystem` + offline `whileAway` that calls `runAutoBuyer`.
- **Synergy upgrades:** e.g. `"bonusPerOwned": "0.01", "synergyOf": "grandma"` on a farm upgrade.
- **Golden offers:** `"golden"` block + `GoldenEventSystem` + `GoldenOffer` (tap quickly when it appears).
- **Save codes + number format:** Settings tab (`SaveCodePanel`; format/decimal mark persist via `PlayerOptions`).
- **Return reminder:** `LogReturnNotifier` prints schedule/cancel — swap for a real notification plugin.

Read the [idle games guide](../concepts/idle-games.md) for how each piece works (prestige layers, cloud save,
analytics, trust model).
''',

  'tutorials/06-agent-api.md': '''# 6 · Drive the engine from an AI agent (MCP, REST, CLI)

Everything the studio and the CLI can do to a project is also an **operation** an agent can call: build a level, validate
it, step the world, undo a mistake. One registry, four doors:

| Door | Use it for |
|---|---|
| `game_agent <group> <verb>` | scripts, CI, humans in a terminal |
| MCP tools (`engine_api`, stdio or HTTP) | Claude Desktop, Claude Code and other MCP clients |
| REST `POST /v1/<group>/<verb>` | your own services |
| JSON-RPC `POST /rpc` | batches, typed clients |

The full list, with every parameter, is the generated [operations reference](../reference/operations.md).

## 1. Start the server

From a checkout of the engine repo:

```bash
cd packages/engine_api
dart run bin/engine_api.dart --project /path/to/your/game
```

That speaks MCP over stdio, which is what MCP clients launch. To use it from Claude Desktop add it to the client\'s MCP
server list:

```json
{
  "mcpServers": {
    "game-engine": {
      "command": "dart",
      "args": ["run", "/path/to/engine/packages/engine_api/bin/engine_api.dart", "--project", "/path/to/your/game"]
    }
  }
}
```

Useful flags: `--read-only` (agent can look but not touch), `--deny \'release.*\'`, `--allow \'level.*\'`.

## 2. What an agent does

A typical session, as tool calls:

1. `project.info`, `schema.components` - what is here, what can an entity hold?
2. `level.create`, `level.add_entity`, `level.move_entity`, `level.paint_tile` - build.
3. `level.validate` / `level.lint` with `playable: true` / `project.problems` - check it. Fix what they report.
4. `world.build` then `world.step` and `world.query` - run the level headlessly and look at the result. Nothing is written.
5. `undo.undo` - take back the last change. Every write is journalled in `.studio/undo/` (the last 100).

Removing things (`level.remove_entity`, `graph.remove_node`, ...) is **destructive**: the first call returns a preview and
a `confirmation` token, the second call with that token applies it. Tokens are tied to the server process and expire
after five minutes.

## 3. The same thing from a shell

```bash
game_agent level add-entity assets/levels/forest.json --name coin --components position
game_agent level lint assets/levels/forest.json --playable
game_agent undo undo
game_agent --read-only level list --json     # the exact result envelope
```

Every command takes `--json` (print the envelope), `--stdin` or `--args \'{...}\'` (parameters as JSON), and writes take
`--dry-run` to preview.

## 4. Over HTTP

```bash
dart run bin/engine_api.dart --http --project /path/to/your/game
TOKEN=\$(cat /path/to/your/game/.studio/api-token)
curl -H "Authorization: Bearer \$TOKEN" -X POST localhost:7421/v1/level/list
curl -H "Authorization: Bearer \$TOKEN" localhost:7421/v1/openapi.json
```

The server listens on localhost only, needs the token for everything except `GET /v1/health`, limits request and result
sizes and rate, and logs each call (no arguments, no results) to `.studio/api-requests.jsonl`. Send an
`Idempotency-Key` header with a write to make retries safe. Configuration can live in `engine_api.yaml` in the project.

## What an agent cannot do

Operations that need the Flutter SDK (`project.create`, `project.upgrade`, `release.build`) exist as CLI commands only
(`game_agent create`, `upgrade`, `build-release`); `engine.capabilities` lists them as unsupported.
''',

  'concepts/ecs.md': '''# The ECS: World, Entity, Component, System

`engine_core`\'s simulation model, in `packages/engine_core/lib/src/ecs/`.

## Entity

An `EntityId` is just an id (see `packages/engine_core/lib/src/ecs/entity.dart`)
— an entity has no data or behavior of its own; it\'s only ever the key
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
world.storeOf<Position>().set(id, Position(100, 100));
final pos = world.storeOf<Position>().get(id); // Position?
final has = world.storeOf<Position>().has(id); // bool
```

A component type must be **registered** before it participates in
`World.toJson()`/`applyPatch()`/`Level.loadInto()` — see
[content-as-data.md](content-as-data.md). Engine built-ins are
registered by `registerCoreComponents`/`registerFlutterComponents`/
`registerPlatformerComponents`; your own game-specific components are
registered the same way via `world.components.register<T>(id, toJson,
fromJson)`. An unregistered component silently can\'t be serialized —
this is a documented common mistake (see `CLAUDE.md`\'s ECS section).

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
tick must run after it. `engine_platformer`\'s `installPlatformerSystems`
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
registerCoreComponents(world); // Position, Velocity, ... (needed once per world)
world.addSystem(MovementSystem());
final id = world.spawn();
world.storeOf<Position>().set(id, Position(0, 0));
world.storeOf<Velocity>().set(id, Velocity(50, 0));
```

`GameRunner` (in `engine_flutter`) creates one `World` per `Scene` and
drives its systems on a fixed timestep each frame — you don\'t call
`update` yourself in a normal Flutter game; you only add systems and
spawn entities in `Scene.populate`.

## Queries

For ad-hoc iteration outside a hand-written system loop (typically in a
`Behavior`, see [agent-api.md](agent-api.md)), `WorldView` provides
`entitiesWith<T>()` and `entitiesWithAll<A, B>()` — see
`packages/engine_core/lib/src/ecs/world_view.dart`.

## Events

`EventBus` (`packages/engine_core/lib/src/ecs/event_bus.dart`) is the
decoupling mechanism between systems that shouldn\'t directly call each
other — e.g. a collision system emitting a "damage" event a combat
system subscribes to, rather than the collision system importing and
calling combat logic directly. See `packages/engine_core/README.md`\'s
"Events" section for the concrete API and `event_helpers.dart` for the
common-case wrappers.

## See also

- [content-as-data.md](content-as-data.md) — serializing/patching a `World` as JSON.
- [agent-api.md](agent-api.md) — the `Behavior`/`WorldView` sandbox for runtime agents.
- [`packages/engine_core/README.md`](../../packages/engine_core/README.md) — full API reference.
''',

  'concepts/idle-games.md': '''# Idle games

The idle / incremental genre layer is **shipped**: create a game with
`game_agent create my_game --template idle_game`, edit `assets/idle_game.json`,
and tune pacing with `game_agent idle simulate` / `idle validate`. Genre UI and
session code live in `engine_idle`; numbers, offline catch-up, economy rules and
the balance simulator live in `engine_core` (`engine_core_idle.dart`) so CLI and
agents can use them without Flutter.

Samples are executed by `packages/engine_core/test/doc_examples_idle_test.dart` and
`packages/engine_idle/test/doc_examples_test.dart`. Remaining idle work (device bench,
cloud-save walkthrough, localisation, research UI, …) lives under Idle polish in
[`TODO.md`](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/TODO.md).

## Creating a new idle game

```bash
game_agent create bakery --template idle_game
cd bakery && flutter run
```

Everything below is available as data and/or a widget. The template wires the
common path; optional blocks are noted.

| Subsystem | Where | In template? |
|---|---|---|
| Resources + generators + upgrades | `assets/idle_game.json` | yes |
| Cost curves (`geometric` / `linear` / `table`) | definition | yes (geometric) |
| Milestones on generators | definition | add when you want |
| Tech gates (`requires` on generators/upgrades) | definition + `TechState` in Dart | opt-in |
| Taps + timed boosts | `IdleController.tap` / `BoostSystem` | yes |
| Achievements | definition + `AchievementList` | yes |
| Prestige (single or layered `prestiges`) | definition + `PrestigePanel` | yes (layered) |
| Challenges | definition + `ChallengePanel` | yes |
| Golden offers | `"golden"` + `GoldenEventSystem` + `GoldenOffer` | yes |
| Auto-buyer | `"autoBuyer"` + `AutoBuySystem` + `whileAway` | yes |
| Synergy upgrades | `"bonusPerOwned"` + `"synergyOf"` | yes (sample) |
| Offline catch-up + lifecycle | `IdleSession` + `IdleLifecycleHost` | yes (cold start + resume; `onDouble` stub) |
| Durable save | web `BrowserSaveStore` / else `FileSaveStore` | yes |
| Export code / cloud hook | `SaveCodePanel` / `CloudSaveStore` | export yes; cloud is a contract |
| Return reminder | `ReturnNotifier` | yes (`LogReturnNotifier` stub) |
| Stats | `StatsPanel` | yes |
| Number formats | `IdleSettingsPanel` / `PlayerOptions` | yes (persisted) |
| Pause / credits / volumes | `showIdlePauseMenu`, `showIdleCredits`, volume sliders | yes |
| SFX hooks | `IdleSfx` on `IdleController` | yes (log stubs; wire `AudioManager`) |
| Prestige shop | `PrestigeShop` / `UpgradeList(costResource:)` | yes (gem sample) |
| Research tree | `"research"` + `ResearchPanel` / `buyResearch` | yes (gates Mine) |
| Time warp | `"timeWarps"` + `TimeWarpPanel` / `buyTimeWarp` | yes (1h for 1 gem) |
| Season pass | `"seasonPass"` + `SeasonPassPanel` / `claimSeasonPass` | yes |
| Localised names | `nameKey` + `StringTable` / `assets/i18n/en.json` | yes |
| Definition JSON Schema | `schema.idle_game` / `idleGameDefinitionJsonSchema` | yes |
| Balance check | `game_agent idle simulate` / `idle.validate` | CLI / agent |
| Headless agent ops | `idle.*` on MCP/REST/CLI | yes |

Automation is on by default in the template (`"autoBuyer"` + `AutoBuySystem()` after
`IdleSystem()`, plus `whileAway:` that calls `runAutoBuyer(world, wallet, buyer)`). Flip
`AutoBuyer.enabled` when the player unlocks it.

![The idle game template after fifty minutes of simulated play: resources and income at the top, a row of buy buttons per generator, greyed-out ones unaffordable](../img/idle-game.png)

## Numbers that do not overflow

An incremental game\'s totals outgrow a 64-bit integer within hours, and a `double` stops at 1e308. `BigNumber`
stores `mantissa * 10^exponent`, so the range is effectively unbounded and arithmetic never overflows:

```dart
final a = BigNumber.parse(\'1.5e300\');
final b = BigNumber.from(2000);
a * b;                     // 3e303
a + BigNumber.one;         // unchanged: a term 17 orders of magnitude smaller is lost, like a double
a.pow(2); a.sqrt(); a.log10(); a.floor();
a > b;                     // total order, also across signs and zero
```

- It keeps about **15 significant digits**. That is the right trade for an idle game and the wrong one for money.
- Division by zero, `NaN` and infinity throw instead of spreading.
- JSON is the string `"1.5e300"`; it round-trips exactly.
- Compare results of long arithmetic chains with `approxEquals`, not `==`.

## Showing them

```dart
formatBigNumber(BigNumber.from(1234567));                                  // 1.23M
formatBigNumber(BigNumber.parse(\'4.5e12\'), style: NumberStyle.scientific); // 4.50e12
formatBigNumber(BigNumber.from(999999));                                   // 1.00M  (rounding carries)
```

Styles: `suffix` (`K M B T Qa Qi Sx Sp Oc No Dc`, then scientific), `scientific`, `engineering`. Numbers below 1000 print
plainly. `decimals` and `decimalSeparator` are configurable.

## Resources: `BigTreasury`

`BigTreasury` is the idle-scale counterpart of the strategy `Treasury`: named resources and per-second income as
`BigNumber`s.

```dart
final wallet = BigTreasury(
  amounts: {\'coins\': BigNumber.from(10)},
  incomePerSecond: {\'coins\': BigNumber.from(5)},
);
wallet.accrue(1.0);                                   // income is rate x time
wallet.spend({\'coins\': BigNumber.from(50000)});       // true, or false and nothing taken
```

`accrue` is correct for any step size: one six-hour step gives the same result as 21,600 one-second steps, which
is what makes offline catch-up cheap. It is a registered component (`bigTreasury`), so it saves with the world.

## Offline progress

```dart
final summary = OfflineProgress.catchUp(
  wallet,
  lastActiveAt: leftAt,       // save this when the app pauses
  now: DateTime.now(),        // pass the clock in; the engine never reads it itself
);
summary.gained;               // {coins: 54000} for the "while you were away" screen
summary.credit.capped;        // true if the absence hit the cap
```

`OfflineConfig` sets the **cap** (default 8 hours), the **efficiency** (fraction of normal income earned away) and
the **minimum** absence (default 30 s; anything shorter earns and shows nothing). A clock that moved *backwards*
grants nothing. `OfflineProgress.untilCap` tells you when the cap will be reached, for a reminder.

!!! warning "Constant rates by default"
    Catch-up assumes your income rates stay the same while away. If your game has automation that spends money
    on upgrades (auto-buyers), pass `whileAway:` to `IdleSession` (or call `OfflineProgress.applyInSlices`): the
    absence is paid in slices (200 by default) and your callback runs between them to buy things and
    `recomputeIncome`, so each slice earns at the then-current rate. It is as accurate as the slice count.

## Describing a whole game as data

`engine_idle` loads an idle game from one JSON file: resources, **generators** (things you buy copies of that
make resources every second), **upgrades** (one-time multipliers), **achievements** and a **prestige** rule.

```json
{
  "resources": { "coins": { "start": "15" }, "gems": {} },
  "generators": [
    { "id": "cursor", "name": "Cursor",
      "cost": { "type": "geometric", "base": "15", "growth": 1.15 },
      "output": { "coins": "0.1" } }
  ],
  "upgrades": [ { "id": "x2", "target": "cursor", "multiplier": "2", "cost": { "coins": "100" } } ],
  "achievements": [ { "id": "rich", "stat": "lifetime:coins", "atLeast": "100000", "reward": "1.1" } ],
  "prestige": { "currency": "gems", "basedOn": "coins", "divisor": "1e6", "exponent": 0.5, "bonusPerUnit": 0.05 },
  "offline": { "capHours": 8, "efficiency": 0.5 }
}
```

```dart
final game = loadIdleDefinition(world, json);   // throws IdleDefinitionException listing every problem
world.addSystem(IdleSystem());                   // accrues income every step
buyGenerator(world, game.wallet, cursor);                  // ×1
buyGenerator(world, game.wallet, cursor, count: null);     // as many as affordable
```

`validateIdleDefinition(json)` returns the problems without throwing, each with its path
(`generators[1].cost.growth must be a number >= 1`), so an editor or an agent can fix them all at once. The full
example is `packages/engine_idle/example/cookie_clicker.json`.

- **Cost curves:** `geometric` (`base * growth^owned`, growth 1.07-1.15 is typical) and `linear`. Buying ×10 or
  "max" uses closed forms, so a budget of 1e200 is answered instantly.
- **Income** is `owned × output × (purchased upgrades targeting it) × (game-wide modifiers)`. Modifiers are named
  sources in `IdleModifiers` (prestige, achievements, boosts), so the player can be told why the number is what it is.
- **Prestige:** gain is `floor((earnedThisRun / divisor) ^ exponent)` of a permanent currency that adds
  `bonusPerUnit` to a game-wide multiplier per unit held. `performPrestige` resets resources, generators and
  (unless `keepUpgrades`) upgrades, and keeps the currency, lifetime stats and achievements.
- **Achievements** are goals over stats (`lifetime:`, `run:`, `owned:`, `prestiges`, `taps`, `seconds`) with an
  optional multiplier reward. Check them with `checkAchievements` after purchases and every few seconds.
- **Taps and boosts:** `tapEarn` and `activateBoost` (a timed multiplier; restarting the same boost refreshes it).

## Saving and returning

`IdleSession` saves the whole world with a version and a timestamp, migrates old saves, and pays offline progress
when the app returns:

```dart
final session = IdleSession(controller: controller, store: FileSaveStore(path),
    migrator: SaveMigrator(currentVersion: 2, migrations: {1: upgradeV1ToV2}),
    offline: game.offline);
final away = session.load();              // restore + offline catch-up; null on a first run
session.startAutosave();                  // every 30 s
```

Wrap the screen in `IdleLifecycleHost(session: session, onAway: showSummary, child: ...)` to save when the app is
backgrounded and settle the time away on return. A crash mid-write falls back to the previous save;
`exportCode()` / `importCode()` move a game between devices as a copyable `GSAVE1...` text; a save from a newer
game is refused with a readable message and left untouched.

## The screens

`IdleController` runs the clock (about ten UI updates a second) and is the one place the UI calls to buy, tap or
prestige. The ready-made widgets read from it: `ResourceHeader`, `GeneratorList` (×1 / ×10 / ×100 / Max, disabled
when unaffordable, lazily built so hundreds of rows stay smooth), `UpgradeList`, `OfflineSummaryDialog`
(with an optional "Double it" button for a rewarded ad: pass `onDouble`, then call `IdleSession.doubleOffline`),
`PrestigePanel` (previews the gain and asks before resetting), `ChallengePanel`, `AchievementList`,
`StatsPanel` (taps / prestiges / play time / earned), `GoldenOffer` and `IdleSettingsPanel`.
`controller.setStyle(NumberStyle.scientific)` switches every number at once (styles: `suffix`, `scientific`,
`engineering`, `grouped`).

## Storage choices

`FileSaveStore` (atomic, with a backup) on mobile and desktop; `BrowserSaveStore` (`localStorage`) on the web;
`MemorySaveStore` in tests. For several devices, implement `CloudSaveStore` over your platform\'s service and call
`IdleSession.syncCloud`: the save from the device that was active later wins, `resolve:` lets you ask the player,
and a pulled save pays no offline time. `SaveCodePanel` lets players move a game by copying text.

### Cloud-save walkthrough

`CloudSaveStore` is only a contract (`fetch` / `push`). The package ships
`HttpCloudSaveStore` with injected HTTP so the same class works on IO, web, and
tests — you supply `getBody` / `putBody`:

```dart
final cloud = HttpCloudSaveStore(
  uri: Uri.parse(\'https://api.example.com/v1/saves/player1\'),
  getBody: (uri) async {
    final res = await http.get(uri, headers: {\'Authorization\': \'Bearer \$token\'});
    if (res.statusCode == 404) return null;
    return res.body;
  },
  putBody: (uri, body) async {
    await http.put(uri, headers: {\'Authorization\': \'Bearer \$token\', \'Content-Type\': \'application/json\'}, body: body);
  },
);
final result = await session.syncCloud(cloud, resolve: (local, remote) {
  // Ask the player which save to keep when both have progress.
  return true; // take remote
});
```

Game Center / Play Games: wrap their cloud-blob APIs the same way (read → JSON
string or null, write → UTF-8 bytes). Keep one authoritative clock when you care
about cheating (see Trust below); `syncCloud` alone is for convenience, not anti-cheat.

## More rules, all data

- **Milestones** on a generator (`"milestones": [{"owned": 25, "multiplier": "2"}]`) multiply its output; the row
  shows progress to the next.
- **Prestige** can keep chosen generators (`"keepGenerators": ["farm"]`) and upgrades (`keepUpgrades`).
- **Challenges** are restricted runs with a goal and a lasting reward: `"challenges": [{"id": "frugal", "rules": ["noUpgrades"],
  "goalStat": "run:coins", "goalAtLeast": "1e6", "reward": "3"}]`. Rules: `noUpgrades`, `noGenerator:<id>`,
  `incomeMultiplier:<factor>`. Starting one restarts the run (`startChallenge`), completing it (settled by
  `checkAchievements`) lifts the rules and multiplies income for good, and `ChallengePanel` lists, starts and abandons them.
- **Prestige layers:** use `"prestiges": [ {...}, {"id": "ascend", "currency": "stars", "basedOn": "gems", "divisor": "100",
  "resetsCurrencies": ["gems"]} ]` instead of a single `"prestige"`. A layer\'s gain counts toward the next layer\'s
  `basedOn`; a layer keeps the other layers\' currencies unless it lists them in `resetsCurrencies`; each has its own
  income bonus (`prestige`, `prestige:<id>`). Call `performPrestige(world, wallet, \'ascend\')` or show a
  `PrestigePanel(controller:, ruleId: \'ascend\')` per layer.
- **Achievements** can count your own events: call `recordIdleEvent(world, wallet, \'dragon_slain\')` and use
  `"stat": "event:dragon_slain"`.
- **Golden events** offer timed random boosts or payouts, reproducible from the seed: a `"golden": {"meanInterval": 90,
  "lifetime": 12, "rewards": [{"kind": "boost", "multiplier": "7", "seconds": 30}, {"kind": "payout", "seconds": 300}]}`
  block in the definition, `GoldenEventSystem(DeterministicRandom(seed))` in the world, and a `GoldenOffer(controller:)` widget
  (or `claimGolden` yourself).
- **Automation:** an `AutoBuyer` (in the definition as `"autoBuyer": {"intervalSeconds": 5, "maxPerRun": 10}`) buys the
  affordable purchase with the best payback on a timer; add `AutoBuySystem()` after `IdleSystem()`, flip `enabled` when
  the player unlocks it, and pass `whileAway:` that reads the buyer and calls `runAutoBuyer(world, wallet, buyer)` so
  offline catch-up also buys. `bestPurchase(world, wallet)` is the same recommendation as a function (for a "buy this next" hint).
- **Synergy upgrades:** `"bonusPerOwned": "0.01", "synergyOf": "grandma"` on an upgrade multiplies the target by
  `1 + bonusPerOwned * owned(synergyOf)` once purchased (stacks with a plain `multiplier` when both are set).
- **Research:** `"research": [{"id": "mining", "cost": {"coins": "5000"}, "unlocks": ["mining"]}]` plus
  `"requires": ["mining"]` on a generator/upgrade. `ResearchPanel` / `buyResearch` spends and `grantTech`s the unlocks.
- **Time warp:** `"timeWarps": [{"id": "hour", "seconds": 3600, "cost": {"gems": "1"}}]` — `TimeWarpPanel` /
  `buyTimeWarp` credits that many seconds of *current* income (not offline efficiency).
- **Season pass:** `"seasonPass": {"id": "spring", "xpStat": "lifetime:coins", "tiers": [{"at": "100", "grant": {"gems": "1"}}]}`
  — XP uses the same stat keys as achievements; `claimSeasonPass` (also called from `checkAchievements`)
  grants resources / multipliers / tech in order. `SeasonPassPanel` shows progress.
- **Localised names:** put `"nameKey": "gen.cursor"` on entities and load `StringTable.fromFlatLocale` from
  `assets/i18n/en.json`; pass it as `IdleController(strings:)`. Literal `name` remains the fallback.
- **Offline double:** pass `onDouble` to `OfflineSummaryDialog` (show a rewarded ad; return `true` if earned), then call
  `IdleSession.doubleOffline(summary)` when the dialog pops `true`. The template stubs `onDouble: () async => true`.
- **Number format persistence:** `IdleSettingsPanel(onStyleChanged:, onDecimalSeparatorChanged:)` — store the values in
  `PlayerOptions` (template uses `numberStyle` / `decimalSeparator` custom keys) and re-apply on boot.
- **Analytics** (`IdleAnalytics`) reports purchases, prestiges and returns through the consent-aware manager.

## Trust: the clock and the save

The engine makes a deliberate, simple choice: **a single-player idle game trusts the device**.

- *The clock.* Offline earnings come from the difference between two device times. `OfflineProgress` never
  grants negative time (the clock moved backwards) or more than the configured cap, so setting the clock
  forward can gain at most one cap\'s worth per return, which is the same as waiting. Time enters only through
  the `clock` you give `IdleSession`, so a game that needs more can pass a server-synchronised clock without
  touching the engine.
- *The save.* `SaveCodec` checksums detect damage, not editing: anyone can change a number and re-sign it. That
  is fine for a game with no shared state.
- *When it is not fine.* Leaderboards, competitive events or real-money purchases need the server to be the
  authority (server time, server-side validation of purchases and scores). That is outside the engine; keep
  the economy deterministic (it is) so a server can replay a claimed history and check it.

## Tuning without playing

`simulateIdle` (also `game_agent idle simulate` and the MCP/REST `idle.simulate` op) plays a definition with a
deterministic greedy strategy (buy the best payback, wait just long enough) and reports when income reaches each
power of ten, when achievements and prestiges happen, and why a design stalls. When `prestigeAt` is set it
prestiges **every** layer that meets the threshold (higher layers first, so a ready ascension is not starved by
cheaper first-layer prestiges); while a challenge is running it does not prestige (that would wipe the challenge\'s
run). Incomplete challenges are started in definition order as soon as none is active (`playChallenges: false`
skips them):

```bash
game_agent idle validate path/to/bakery/assets/idle_game.json
game_agent idle simulate path/to/bakery/assets/idle_game.json --days 3 --prestige-at 1.0
```

From an engine checkout you can also run
`dart run tool/simulate.dart example/cookie_clicker.json --days 3 --prestige-at 1.0` inside
`packages/engine_idle`. Use it to check that the early game is not a wall and that prestige pays at a sensible
time; it is a fair baseline, not an optimal player.
''',

  'concepts/settings.md': '''# Settings and accessibility options

`PlayerOptions` is the data model for a player\'s settings; `PlayerOptionsManager` loads, changes,
saves and announces them; `SettingsMenuScene` draws a menu bound to them. **The engine stores and
presents the options. Applying them to the game is your code\'s job** - see
[What the engine applies](#what-the-engine-applies).

Samples are executed by `packages/engine_core/test/doc_examples_player_options_test.dart` and
`packages/engine_flutter/test/doc_examples_settings_test.dart`.

## The options

| Group | Fields |
|---|---|
| Audio | `masterVolume`, `musicVolume`, `sfxVolume` (0..1) |
| Controls | `controlScheme`, `keyboardBindings`, `gamepadBindings`, `touchBindings` (action -> key/button) |
| Accessibility | `textScale` (0.5..3), `highContrast`, `colorblindMode` (`none`, `protanopia`, `deuteranopia`, `tritanopia`), `reduceMotion`, `screenShakeIntensity` (0..1), `dialogueSpeed` |
| Other | `locale`, `showFpsOverlay`, and a free-form `custom` map for your own keys |

Everything has a default, and `PlayerOptions.fromJson` fills in whatever a saved file lacks, so adding
an option in a later version never breaks an old save.

## Load, change, save, listen

```dart
final storage = InMemoryPlayerOptionsStorage();           // tests; see persistence below
final options = PlayerOptionsManager(storage);
options.addListener((o) => audio.setMasterVolume(o.masterVolume));

await options.load();                                     // defaults if nothing is stored

await options.setOption(\'masterVolume\', 0.4);             // one value
await options.update((o) => o.copyWith(reduceMotion: true, textScale: 1.5));   // several
await options.setOption(\'difficulty\', \'hard\');            // unknown key -> options.custom
options.getOption(\'masterVolume\');                        // 0.4
```

- Every change is **clamped** (volumes to 0..1, `textScale` to 0.5..3, shake to 0..1), saved to
  storage and then sent to listeners.
- `load()` also notifies, so UI built from the options initialises itself from one place.
- Keep the manager somewhere long-lived (your `Game`), not in a scene.

## Persistence

Storage is an interface (`PlayerOptionsStorage`: `load`, `save`, `clear`). `engine_flutter` provides
`SharedPreferencesPlayerOptionsStorage`, and `createPlayerOptionsManager()` builds a manager on it and
loads it:

```dart
final options = await createPlayerOptionsManager();       // survives restarts on every platform
```

An unreadable stored value is treated as "nothing stored" rather than crashing.

## A settings menu

Subclass `SettingsMenuScene`, give it the manager, and list widgets; each is bound to an option key and
writes back through the manager. Types: toggle, slider, dropdown, list, key binding, section header.

```dart
class MySettings extends SettingsMenuScene {
  @override
  String? get title => \'Settings\';

  @override
  List<SettingsWidgetSpec> get widgets => const [
        SettingsSliderSpec(id: \'vol\', label: \'Volume\', optionKey: \'masterVolume\', min: 0, max: 1),
        SettingsToggleSpec(id: \'motion\', label: \'Reduce motion\', optionKey: \'reduceMotion\'),
      ];

  @override
  void onValueChanged(String key, dynamic value) {
    // Apply immediately, e.g. audio.setMasterVolume(value) when key == \'masterVolume\'.
  }
}

scenes.pushSettingsMenu(MySettings()..optionsManager = options);   // as an overlay
```

`AccessibilitySettingsMenu` is ready-made, with high contrast, colorblind mode, reduce motion, text size
and shake intensity.

## What the engine applies

Be clear about this when you ship an accessibility menu:

- **Camera shake has a switch:** `Camera.shakeIntensity` multiplies every shake (`0` none, `1` as authored).
  Bind it once: `options.addListener((o) => camera.shakeIntensity = o.screenShakeIntensity);`. The engine does
  not read `PlayerOptions` itself.
- **Not applied by the engine:** volumes, `textScale`, `highContrast`, `reduceMotion`, `dialogueSpeed`. They
  are values for *your* systems to honour (skip your own animations when `reduceMotion` is on, scale your own
  UI text, and so on).

- **`colorblindMode`:** override `Game.colorblindMode` (templates read `PlayerOptions`) so
  `GameRunner` passes it into `EngineView`\'s colour-matrix filter each frame.
- **`screenShakeIntensity`:** override `Game.screenShakeIntensity` the same way; `GameRunner`
  applies it to the scene camera.
- `showFpsOverlay` as a `GameConfig` field does work (debug builds); the option is just the player-facing
  switch for you to wire to it.

A setting the player can change that does nothing is worse than no setting, so wire the options you
expose and leave the others out of your menu.
''',

  'reference/operations.md': '''# Operations

<!-- Generated by `dart run tool/gen_api_docs.dart` in packages/engine_api. Do not edit. -->

Every operation is a CLI command, an MCP tool, a REST route and a JSON-RPC method. Reads change nothing; writes apply immediately and can be undone with `undo.undo`; destructive writes return a preview and a confirmation token first. Results are `{ok, data, warnings, diff?, undoId?, durationMs}` or `{ok:false, error:{code, message, hint?}}`.

## asset

### `asset.atlas_regions`

The named regions of one atlas, with their rectangles.

Look the atlas up by the id `asset.index` shows. Region objects are returned as the manifest stores them.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `atlas` | string; required | |

Errors: `not_found`.

```bash
game_agent asset atlas-regions <atlas>
```

REST: `POST /v1/asset/atlas_regions` · MCP tool: `asset.atlas_regions` · JSON-RPC method: `asset.atlas_regions`

### `asset.index`

List the project\'s atlases, images, audio, data files and prefabs.

Atlases come from `assets/studio_atlases.json` (which gives them an id levels can use as `atlasId`) and from any `X.json` with a `regions` map next to `X.png` (what `game_agent pack-assets` / `asset.pack` writes). Images already part of an atlas are not listed again under `images`.

*read*, needs an open project, idempotent.

```bash
game_agent asset index
```

REST: `POST /v1/asset/index` · MCP tool: `asset.index` · JSON-RPC method: `asset.index`

### `asset.pack`

Pack every image under a directory into one sprite sheet + region manifest.

Recursively loads images under `input`, MaxRects-packs them (with optional resolution tiers via `scales`), and proposes the PNG sheet(s) plus JSON manifest(s) that `SpriteAtlas.fromManifest` reads. Needs an [ImageCodec] on the context (`engine_cli` / `engine_api` inject one); without it returns `unsupported`. Same behaviour as `game_agent pack-assets`.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `input` | path; required | Directory of source images (scanned recursively). |
| `outputImage` | path; default `"assets/packed/atlas.png"` | |
| `outputManifest` | path | Defaults to outputImage with a .json extension. |
| `padding` | integer; default `2`; 0 to 64 | |
| `maxWidth` | integer; default `2048`; 1 to 16384 | |
| `scales` | string; default `"1.0"` | Comma-separated tiers, e.g. "1.0,0.5,0.25". |
| `maxAttempts` | integer; default `20`; 1 to 100 | Grow-and-retry attempts before giving up. |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `unsupported`, `not_found`, `validation_failed`, `internal`.

```bash
game_agent asset pack
```

REST: `POST /v1/asset/pack` · MCP tool: `asset.pack` · JSON-RPC method: `asset.pack`

## engine

### `engine.capabilities`

List operation groups, unsupported operations and the active restrictions.

Tells a client what to expect before it calls anything: how many operations each group has, which ones exist but are not served here (they need the Flutter SDK), whether the server is read-only and which operations the allow/deny lists hide.

*read*, idempotent.

```bash
game_agent engine capabilities
```

REST: `POST /v1/engine/capabilities` · MCP tool: `engine.capabilities` · JSON-RPC method: `engine.capabilities`

### `engine.docs`

List documentation pages, or return one page as markdown.

With a docs root (`engine_api --docs-root` / `OpContext.docsRoot`) reads the local `docs/` tree: omit `page` to list readable `.md` files (drafts under `proposals/` and the studio QA checklist excluded); with `page` returns `{page, markdown, source: local}`. Without a docs root, serves the curated package bundle (`source: bundled`, markdown bodies for `kRemoteDocsPages`) so agents offline still get full pages; `url` / `docsUrl` remain for the site.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `page` | string | Docs-relative path (`.md` optional), e.g. concepts/ecs. |

Errors: `not_found`.

```bash
game_agent engine docs <page>
```

REST: `POST /v1/engine/docs` · MCP tool: `engine.docs` · JSON-RPC method: `engine.docs`

### `engine.health`

Report that the server is alive, its versions and whether a project is open.

Cheap liveness and identity check. Safe to call at any time; changes nothing.

*read*, idempotent.

```bash
game_agent engine health
```

REST: `POST /v1/engine/health` · MCP tool: `engine.health` · JSON-RPC method: `engine.health`

### `engine.operation`

Describe one operation: parameters as JSON Schema, errors, examples.

Everything needed to call an operation correctly, including its input JSON Schema.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `name` | string; required | group.verb |

Errors: `not_found`.

```bash
game_agent engine operation <name>
```

REST: `POST /v1/engine/operation` · MCP tool: `engine.operation` · JSON-RPC method: `engine.operation`

### `engine.operations`

List every operation (name, kind, scope, summary), optionally filtered.

The catalogue. Filter by `group` or `kind`; operations hidden by the allow/deny lists are not listed.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `group` | string | Only this group, e.g. level. |
| `kind` | enumeration; one of `read`, `write`, `destructive` | |

```bash
game_agent engine operations
```

REST: `POST /v1/engine/operations` · MCP tool: `engine.operations` · JSON-RPC method: `engine.operations`

## graph

### `graph.add_node`

Add a node of a kind; the first node becomes the entry.

The id defaults to `<kind><index>`. Parameters start at the kind\'s defaults (non-dialogue graphs) and `params` overrides them. Problems with the graph so far come back as warnings.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `kind` | string; required | |
| `id` | string | |
| `params` | object | |
| `x` | number; default `0` | |
| `y` | number; default `0` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent graph add-node <path>
```

REST: `POST /v1/graph/add_node` · MCP tool: `graph.add_node` · JSON-RPC method: `graph.add_node`

### `graph.compile`

Compile a behavior tree or state machine graph to engine JSON.

Behavior-tree children follow the canvas left to right. Dialogue graphs have no single compiled form here (`compiled` is null). With `output` the JSON is also written there.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `output` | path | |
| `id` | string; default `"fsm"` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `validation_failed`.

```bash
game_agent graph compile <path>
```

REST: `POST /v1/graph/compile` · MCP tool: `graph.compile` · JSON-RPC method: `graph.compile`

### `graph.connect`

Connect an output port to an input port of the same type.

Ports are checked against the node kinds; a mismatch is `validation_failed` and nothing is written.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `from` | string; required | |
| `fromPort` | string; required | |
| `to` | string; required | |
| `toPort` | string; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent graph connect <path>
```

REST: `POST /v1/graph/connect` · MCP tool: `graph.connect` · JSON-RPC method: `graph.connect`

### `graph.create`

Create an empty graph file.

Files live under `graphs/`. Fails with `conflict` when the file exists.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `type` | enumeration; default `"dialogue"`; one of `dialogue`, `behaviorTree`, `stateMachine` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `conflict`.

```bash
game_agent graph create <path>
```

REST: `POST /v1/graph/create` · MCP tool: `graph.create` · JSON-RPC method: `graph.create`

### `graph.disconnect`

Remove one connection.

Exact match on both ends; `not_found` when there is no such edge.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `from` | string; required | |
| `fromPort` | string; required | |
| `to` | string; required | |
| `toPort` | string; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent graph disconnect <path>
```

REST: `POST /v1/graph/disconnect` · MCP tool: `graph.disconnect` · JSON-RPC method: `graph.disconnect`

### `graph.list`

List the project\'s graphs with their type and node count.

Every `graphs/*.json`.

*read*, needs an open project, idempotent.

```bash
game_agent graph list
```

REST: `POST /v1/graph/list` · MCP tool: `graph.list` · JSON-RPC method: `graph.list`

### `graph.node_kinds`

The node kinds available for a graph type, with ports and parameters.

Ports are typed (flow, string, number, boolean, entity, event); `connect` only joins equal types.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `type` | enumeration; default `"dialogue"`; one of `dialogue`, `behaviorTree`, `stateMachine` | |

```bash
game_agent graph node-kinds <type>
```

REST: `POST /v1/graph/node_kinds` · MCP tool: `graph.node_kinds` · JSON-RPC method: `graph.node_kinds`

### `graph.read`

Read a graph file.

The file as saved: type, graph (nodes, edges, variables, entryNodeId) and canvas layout.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |

```bash
game_agent graph read <path>
```

REST: `POST /v1/graph/read` · MCP tool: `graph.read` · JSON-RPC method: `graph.read`

### `graph.remove_node`

Remove a node and every edge touching it.

Destructive: previews first. Clears the entry node if it was this one.

*destructive*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `id` | string; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent graph remove-node <path>
```

REST: `POST /v1/graph/remove_node` · MCP tool: `graph.remove_node` · JSON-RPC method: `graph.remove_node`

### `graph.set_param`

Set one parameter of a node.

Free-form: the value is stored as given. Use graph.node_kinds to see what a kind expects.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `node` | string; required | |
| `param` | string; required | |
| `value` | json; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent graph set-param <path>
```

REST: `POST /v1/graph/set_param` · MCP tool: `graph.set_param` · JSON-RPC method: `graph.set_param`

### `graph.validate`

Check a graph for unknown kinds, mismatched ports, unreachable nodes and cycles.

Uses the checks of the graph\'s type (trees check shape, state machines allow loops). `ok` is false when any issue exists.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |

```bash
game_agent graph validate <path>
```

REST: `POST /v1/graph/validate` · MCP tool: `graph.validate` · JSON-RPC method: `graph.validate`

## i18n

### `i18n.keys`

Report every i18n key, which locales have it, and placeholder mismatches.

Reads `assets/i18n/<locale>.json` files (flat `{ "key": "text" }` maps — the same shape the studio uses for its own catalogs). Without `locale`, compares every file; with `locale`, that file is checked against the union of keys from all locales. `missing` lists keys absent from a locale; `placeholderMismatches` lists keys whose `{name}` placeholders differ across locales. `ok` is true when both are empty.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `locale` | string | Focus the missing report on this locale (e.g. fa). |

```bash
game_agent i18n keys
```

REST: `POST /v1/i18n/keys` · MCP tool: `i18n.keys` · JSON-RPC method: `i18n.keys`

### `i18n.set`

Set one key\'s text in a locale catalog.

Writes `assets/i18n/<locale>.json` (creates the file when missing). Keys are sorted on write so diffs stay stable. Undoable via `undo.undo`.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `locale` | string; required | |
| `key` | string; required | |
| `text` | string; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent i18n set <locale>
```

REST: `POST /v1/i18n/set` · MCP tool: `i18n.set` · JSON-RPC method: `i18n.set`

## idle

### `idle.best_purchase`

The purchase the greedy advisor would make next, with its cost and income gain.

Loads the definition at its starting state (optionally with `owned` counts applied to generators) and asks the same advisor the auto-buyer and balance simulator use. `null` data means nothing adds income.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path | |
| `json` | json | |
| `owned` | object | Generator id -> copies already owned. |
| `mainResource` | string; default `"coins"` | |

Errors: `validation_failed`.

```bash
game_agent idle best-purchase <path>
```

REST: `POST /v1/idle/best_purchase` · MCP tool: `idle.best_purchase` · JSON-RPC method: `idle.best_purchase`

### `idle.format_number`

Write a big number the way the game shows it (1.5M, 1.5e6, 1,500,000).

Values are strings like "1.5e300" because they do not fit a double.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `value` | string; required | |
| `style` | enumeration; default `"suffix"`; one of `suffix`, `scientific`, `engineering`, `grouped` | |
| `decimals` | integer; default `2`; 0 to 10 | |

```bash
game_agent idle format-number <value>
```

REST: `POST /v1/idle/format_number` · MCP tool: `idle.format_number` · JSON-RPC method: `idle.format_number`

### `idle.simulate`

Play an idle game with a deterministic greedy strategy and report its pacing.

Always buys the best-payback purchase, waiting just long enough to afford it, and prestiges any layer when it would give `prestigeAt` times what is held of that layer\'s currency (higher layers first). Incomplete challenges are played in order unless `playChallenges` is false. Same input, same report. Use it to tune cost curves without playing.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path | |
| `json` | json | |
| `days` | number; default `3`; 0.01 to 3650 | |
| `prestigeAt` | number; 0.01 to ∞ | Prestige a layer once its gain is this many times what is held of that layer\'s currency. |
| `playChallenges` | boolean; default `true` | Start and complete incomplete challenges in definition order. |
| `mainResource` | string; default `"coins"` | |

Errors: `validation_failed`.

```bash
game_agent idle simulate <path>
```

REST: `POST /v1/idle/simulate` · MCP tool: `idle.simulate` · JSON-RPC method: `idle.simulate`

### `idle.state`

The wallet, income and owned counts of an idle game after a simulated stretch of play.

Loads the definition and, when `afterSeconds` is above zero, plays it with the greedy balance simulator for that long (no prestige). Numbers are formatted strings because they exceed a double.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path | |
| `json` | json | |
| `afterSeconds` | integer; default `0`; 0 to 31536000 | |
| `mainResource` | string; default `"coins"` | |

Errors: `validation_failed`.

```bash
game_agent idle state <path>
```

REST: `POST /v1/idle/state` · MCP tool: `idle.state` · JSON-RPC method: `idle.state`

### `idle.validate`

Check an idle game definition and list every problem with its path.

Give `path` (a project file such as assets/idle_game.json) or inline `json`. Nothing is run or written.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path | |
| `json` | json | The definition, instead of a file. |

```bash
game_agent idle validate <path>
```

REST: `POST /v1/idle/validate` · MCP tool: `idle.validate` · JSON-RPC method: `idle.validate`

## level

### `level.add_component`

Attach a component at its schema defaults, optionally overriding fields.

Conflicts when the entity already has the component; use level.set_field to change one.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entity` | string; required | |
| `component` | string; required | |
| `values` | object | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `conflict`.

```bash
game_agent level add-component <path>
```

REST: `POST /v1/level/add_component` · MCP tool: `level.add_component` · JSON-RPC method: `level.add_component`

### `level.add_entity`

Add an entity whose components start at their schema defaults.

`components` names components to attach at their template values; `values` overrides fields as `{component: {field: value}}`. `index` inserts at a position, default is the end.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `name` | string | |
| `components` | array | |
| `index` | integer; 0 to ∞ | |
| `values` | object | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level add-entity <path>
```

REST: `POST /v1/level/add_entity` · MCP tool: `level.add_entity` · JSON-RPC method: `level.add_entity`

### `level.create`

Create a new level file, empty or from inline entities.

Fails with `conflict` when the file exists. `entities` is the level\'s entity list; omit it for an empty level.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entities` | json | Entity list. |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `conflict`.

```bash
game_agent level create <path>
```

REST: `POST /v1/level/create` · MCP tool: `level.create` · JSON-RPC method: `level.create`

### `level.diff`

What differs between two levels, by entity and component.

Entities are matched by name. Each side is a project file (`a`, `b`) or inline JSON (`aJson`, `bJson`). The result has the structured diff and the same text `game_agent studio diff` prints.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `a` | path | |
| `b` | path | |
| `aJson` | json | |
| `bJson` | json | |

```bash
game_agent level diff <a> <b>
```

REST: `POST /v1/level/diff` · MCP tool: `level.diff` · JSON-RPC method: `level.diff`

### `level.export_canonical`

Rewrite levels in the canonical format (indent, key order).

Only formatting changes. A level that does not load is skipped and listed under `skipped`. Without `paths` every level of the project is processed.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `paths` | array | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level export-canonical
```

REST: `POST /v1/level/export_canonical` · MCP tool: `level.export_canonical` · JSON-RPC method: `level.export_canonical`

### `level.export_tmx`

Write a level\'s tile map as a Tiled .tmx file.

Only tiles and the four collision sets (solid, one-way, slopes) survive; ladders, conveyors, friction, extra layers, animations and atlas binding are listed under `lost`. Default output is next to the level.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entity` | string | Entity holding the tileMap; default the first with one. |
| `output` | path | |
| `image` | string; default `"tiles.png"` | |
| `tileset` | string; default `"tiles"` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level export-tmx <path>
```

REST: `POST /v1/level/export_tmx` · MCP tool: `level.export_tmx` · JSON-RPC method: `level.export_tmx`

### `level.fill_region`

Flood-fill the connected tiles matching the tile at col,row.

Four-connected fill, like the studio\'s bucket tool. Returns how many tiles changed.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entity` | string; required | |
| `col` | integer; required; 0 to ∞ | |
| `row` | integer; required; 0 to ∞ | |
| `tileId` | integer; required; 0 to ∞ | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level fill-region <path>
```

REST: `POST /v1/level/fill_region` · MCP tool: `level.fill_region` · JSON-RPC method: `level.fill_region`

### `level.import_tmx`

Create a level from a Tiled .tmx map.

Makes a new level whose single entity holds the imported tileMap. Fails with `conflict` if the output exists. Unsupported maps (several layers or tilesets, external tilesets, non-CSV data) are `validation_failed` with the reason.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `tmx` | path; required | |
| `output` | path | Default: assets/levels/<tmx name>.json. |
| `entity` | string; default `"ground"` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `conflict`.

```bash
game_agent level import-tmx <tmx>
```

REST: `POST /v1/level/import_tmx` · MCP tool: `level.import_tmx` · JSON-RPC method: `level.import_tmx`

### `level.lint`

Check a level loads and, optionally, that every entity is reachable from the spawn.

Always checks structure like the engine loader. With `playable:true` it also walks, falls and jumps over the tileMap from the spawn (a positioned entity named with "player" or "spawn") to every other positioned entity - the same heuristic the studio validator uses. A conservative model, not a physics simulation: it can pass a level that needs wall jumps or ladders. With `includeRender:true` and an [ImageCodec] on the context, the result also carries a base64 PNG structural preview (`pngBase64`) — the same image `game_agent lint --render` writes. Without a codec, `includeRender` adds a problem instead of failing the whole call. `ok` is false when something fails; `problems` says what.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path | |
| `json` | json | |
| `playable` | boolean; default `false` | |
| `includeRender` | boolean; default `false` | Include a base64 PNG structural preview of the tileMap (needs ImageCodec). |

```bash
game_agent level lint <path>
```

REST: `POST /v1/level/lint` · MCP tool: `level.lint` · JSON-RPC method: `level.lint`

### `level.list`

List the project\'s level files with their entity count and lock state.

Every `.json` under `assets/levels` except the play-test snapshot. `lockedBy` appears when someone holds the advisory lock.

*read*, needs an open project, idempotent.

```bash
game_agent level list
```

REST: `POST /v1/level/list` · MCP tool: `level.list` · JSON-RPC method: `level.list`

### `level.lock`

Take the advisory edit lock on a level.

Writes `<level>.lock` naming this session as owner. Other writers are refused while a live lock is held; a lock older than two hours counts as abandoned. Conflicts when someone else holds it.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `locked`.

```bash
game_agent level lock <path>
```

REST: `POST /v1/level/lock` · MCP tool: `level.lock` · JSON-RPC method: `level.lock`

### `level.lock_status`

Who holds the advisory lock on a level, if anyone.

Reads `<level>.lock`. A lock older than two hours is treated as abandoned and reported as unlocked.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |

```bash
game_agent level lock-status <path>
```

REST: `POST /v1/level/lock_status` · MCP tool: `level.lock_status` · JSON-RPC method: `level.lock_status`

### `level.merge`

Three-way merge two edits of a level.

Per entity and component: one-sided changes win, identical changes apply once, differing ones are conflicts (ours is kept in the result). Without `output` only the merged level is returned. With `output` it is written, but never while conflicts remain.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `base` | path; required | |
| `ours` | path; required | |
| `theirs` | path; required | |
| `output` | path | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `conflict`.

```bash
game_agent level merge
```

REST: `POST /v1/level/merge` · MCP tool: `level.merge` · JSON-RPC method: `level.merge`

### `level.move_entity`

Set an entity\'s position.

Writes the `position` component (created when absent).

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `name` | string; required | |
| `x` | number; required | |
| `y` | number; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level move-entity <path>
```

REST: `POST /v1/level/move_entity` · MCP tool: `level.move_entity` · JSON-RPC method: `level.move_entity`

### `level.paint_tile`

Set one tile of an entity\'s tileMap (0 erases).

The entity needs a `tileMap` component; `col`/`row` must be inside its grid.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entity` | string; required | |
| `col` | integer; required; 0 to ∞ | |
| `row` | integer; required; 0 to ∞ | |
| `tileId` | integer; required; 0 to ∞ | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level paint-tile <path>
```

REST: `POST /v1/level/paint_tile` · MCP tool: `level.paint_tile` · JSON-RPC method: `level.paint_tile`

### `level.read`

Read a level, one entity of it, or selected components.

Returns the level JSON. `entity` narrows to one named entity; `components` keeps only those components of each returned entity. Large levels can be paged with `entityOffset` and `entityLimit`.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entity` | string | Only the entity with this name. |
| `components` | array | Only these components. |
| `entityOffset` | integer; default `0`; 0 to ∞ | |
| `entityLimit` | integer; default `1000`; 1 to 5000 | |

Errors: `not_found`.

```bash
game_agent level read <path>
```

REST: `POST /v1/level/read` · MCP tool: `level.read` · JSON-RPC method: `level.read`

### `level.remove_component`

Detach a component from an entity.

Destructive: previews first and needs `apply` plus the confirmation token.

*destructive*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entity` | string; required | |
| `component` | string; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level remove-component <path>
```

REST: `POST /v1/level/remove_component` · MCP tool: `level.remove_component` · JSON-RPC method: `level.remove_component`

### `level.remove_entity`

Remove a named entity from a level.

Destructive: previews first and needs `apply` plus the confirmation token.

*destructive*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `name` | string; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level remove-entity <path>
```

REST: `POST /v1/level/remove_entity` · MCP tool: `level.remove_entity` · JSON-RPC method: `level.remove_entity`

### `level.set_field`

Set one field of one component of an entity.

Creates the component when absent. The edited level must still validate.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entity` | string; required | |
| `component` | string; required | |
| `field` | string; required | |
| `value` | json; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level set-field <path>
```

REST: `POST /v1/level/set_field` · MCP tool: `level.set_field` · JSON-RPC method: `level.set_field`

### `level.set_layer`

Set the draw order (zIndex) of one component of an entity.

The component must already exist on the entity.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `entity` | string; required | |
| `component` | string; required | |
| `z` | integer; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent level set-layer <path>
```

REST: `POST /v1/level/set_layer` · MCP tool: `level.set_layer` · JSON-RPC method: `level.set_layer`

### `level.unlock`

Release the advisory edit lock on a level.

Only the owner releases a live lock unless `force` is true.

*write*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `force` | boolean; default `false` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `locked`.

```bash
game_agent level unlock <path>
```

REST: `POST /v1/level/unlock` · MCP tool: `level.unlock` · JSON-RPC method: `level.unlock`

### `level.validate`

Check a level (a project file or inline JSON) against the component schemas.

Reports schema errors and warnings. Give either `path` or `json`. Nothing is written. Use `project.validate` for every level at once.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path | |
| `json` | json | The level content, instead of a file. |

```bash
game_agent level validate <path>
```

REST: `POST /v1/level/validate` · MCP tool: `level.validate` · JSON-RPC method: `level.validate`

## prefab

### `prefab.list`

List the project\'s prefabs.

Every `prefabs/*.json`, with its entity count.

*read*, needs an open project, idempotent.

```bash
game_agent prefab list
```

REST: `POST /v1/prefab/list` · MCP tool: `prefab.list` · JSON-RPC method: `prefab.list`

### `prefab.place`

Place a prefab into a level at x,y.

Fresh copies are added at the end of the level; entity names are made unique (`torch` becomes `torch2`).

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `prefab` | string; required | |
| `x` | number; default `0` | |
| `y` | number; default `0` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent prefab place <path>
```

REST: `POST /v1/prefab/place` · MCP tool: `prefab.place` · JSON-RPC method: `prefab.place`

### `prefab.read`

Read one prefab.

The prefab JSON: its name and entities, positions relative to its origin.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `name` | string; required | |

Errors: `not_found`.

```bash
game_agent prefab read <name>
```

REST: `POST /v1/prefab/read` · MCP tool: `prefab.read` · JSON-RPC method: `prefab.read`

### `prefab.save`

Capture named entities of a level as a prefab.

Positions are stored relative to the group\'s top-left corner so the prefab can be placed anywhere. An existing prefab of the same name is replaced (undoable).

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |
| `name` | string; required | |
| `entities` | array; required | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent prefab save <path>
```

REST: `POST /v1/prefab/save` · MCP tool: `prefab.save` · JSON-RPC method: `prefab.save`

## project

### `project.close`

Close the open project.

Forgets the open project; project operations fail until another is opened.

*read*, needs an open project, idempotent.

Errors: `forbidden`.

```bash
game_agent project close
```

REST: `POST /v1/project/close` · MCP tool: `project.close` · JSON-RPC method: `project.close`

### `project.create`

Generate a new game project from a starter template (needs the Flutter SDK; available from the CLI).

Implemented by `game_agent create` because it runs `flutter create` and `pub get`; servers without Flutter list it under `engine.capabilities.unsupported`.

*write*, **CLI only (needs the Flutter SDK)**.

| Parameter | Type | Description |
|---|---|---|
| `name` | string; required | |
| `template` | enumeration; default `"default_game"`; one of `default_game`, `strategy_game`, `idle_game` | |
| `org` | string; default `"com.example"` | |
| `outputDir` | string; default `"."` | |
| `ref` | string; default `"main"` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent project create <name>
```

### `project.git_status`

Which files git sees as changed (empty when the project is not in a git repository).

M modified, A added, D deleted, R renamed, ? untracked, ! conflicted. Paths are relative to the project.

*read*, needs an open project, idempotent.

```bash
game_agent project git-status
```

REST: `POST /v1/project/git_status` · MCP tool: `project.git_status` · JSON-RPC method: `project.git_status`

### `project.info`

Name, version, engine refs and counts of the open project.

Read from `pubspec.yaml` and the project folders. Counts levels, graphs, prefabs and Dart files.

*read*, needs an open project, idempotent.

```bash
game_agent project info
```

REST: `POST /v1/project/info` · MCP tool: `project.info` · JSON-RPC method: `project.info`

### `project.manifest`

Write or update `project.json` (name, engine version, levels).

Merges into any existing `project.json`, keeping unknown keys (notes). `name` and `engineVersion` come from `pubspec.yaml`; `levels` lists every JSON under `assets/levels`. Undoable. Same payload as `game_agent studio project-manifest`.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent project manifest
```

REST: `POST /v1/project/manifest` · MCP tool: `project.manifest` · JSON-RPC method: `project.manifest`

### `project.open`

Open a game project folder; every project operation then works inside it.

Sets the one open project of this session. The folder must contain `pubspec.yaml` and game assets (`assets/levels`, `assets/idle_game.json`, and/or `assets/game_config.json`). This is the only operation that takes an absolute path. Servers started with a fixed `--project` refuse it.

*read*.

| Parameter | Type | Description |
|---|---|---|
| `path` | string; required | Absolute or working-directory-relative project folder. |

Errors: `not_found`, `forbidden`.

```bash
game_agent project open <path>
```

REST: `POST /v1/project/open` · MCP tool: `project.open` · JSON-RPC method: `project.open`

### `project.problems`

Every problem in the project\'s levels, graphs and idle game as one flat list.

Combines `project.validate` (levels), the graph validators and the idle definition check. Each entry has the file, a severity (`error` or `warning`) and a message; fix errors first. Empty means the project is clean.

*read*, needs an open project, idempotent.

```bash
game_agent project problems
```

REST: `POST /v1/project/problems` · MCP tool: `project.problems` · JSON-RPC method: `project.problems`

### `project.read_file`

Read one text file of the project.

Any UTF-8 text file inside the project, up to 1 MiB. Binary files are refused, and so is the API token (`.studio/api-token`).

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path; required | |

Errors: `not_found`, `too_large`, `forbidden`.

```bash
game_agent project read-file <path>
```

REST: `POST /v1/project/read_file` · MCP tool: `project.read_file` · JSON-RPC method: `project.read_file`

### `project.search`

Find text in the project\'s code, level, graph and data files.

Case-insensitive substring search, as the studio\'s Find in project. Returns file, line and the line text.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `query` | string; required | |
| `limit` | integer; default `200`; 1 to 2000 | |

```bash
game_agent project search <query>
```

REST: `POST /v1/project/search` · MCP tool: `project.search` · JSON-RPC method: `project.search`

### `project.symbols`

The names a project defines: its classes, atlas ids, entity names and the engine\'s components.

Found by scanning `lib/*.dart` for class declarations, `assets/studio_atlases.json`, the entity names of every level and the component schemas. Use `prefix` to get completions (case-sensitive) instead of the full lists.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `prefix` | string | Only names starting with this. |

```bash
game_agent project symbols
```

REST: `POST /v1/project/symbols` · MCP tool: `project.symbols` · JSON-RPC method: `project.symbols`

### `project.tree`

List the project files (generated and hidden folders left out), optionally by kind.

The same tree the studio shows. `filter` keeps one kind of file: code, level, graph, image, data or other.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `filter` | enumeration; default `"all"`; one of `all`, `code`, `level`, `graph`, `image`, `data`, `other` | |
| `limit` | integer; default `2000`; 1 to 20000 | |

```bash
game_agent project tree
```

REST: `POST /v1/project/tree` · MCP tool: `project.tree` · JSON-RPC method: `project.tree`

### `project.upgrade`

Upgrade a project to the current engine version (needs the Flutter SDK; available from the CLI).

Implemented by `game_agent upgrade` because it runs `flutter pub upgrade`.

*write*, needs an open project, **CLI only (needs the Flutter SDK)**.

| Parameter | Type | Description |
|---|---|---|
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent project upgrade
```

### `project.validate`

Check every level in the project against the component schemas.

Loads each file under `assets/levels` (not the play-test snapshot) and reports schema errors and warnings per file, like `game_agent studio validate`. `strict` also counts warnings as failures in `ok`.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `strict` | boolean; default `false` | Treat warnings as failures. |

```bash
game_agent project validate
```

REST: `POST /v1/project/validate` · MCP tool: `project.validate` · JSON-RPC method: `project.validate`

## release

### `release.build`

Build a signed Android AAB and/or iOS IPA (needs the Flutter SDK; available from the CLI).

Runs `flutter build`. Implemented by `game_agent build-release` because it needs the Flutter SDK and runs for minutes; servers without Flutter list it under `engine.capabilities.unsupported`.

*write*, needs an open project, **CLI only (needs the Flutter SDK)**.

| Parameter | Type | Description |
|---|---|---|
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

```bash
game_agent release build
```

### `release.plan`

Plan an Android or iOS release build (command, files, problems) without running it.

The same planning `game_agent build-release` does: the exact `flutter build` command line, the files it would create (their paths only; contents can hold secrets and are never returned), errors such as a missing signing setup and warnings. Pass the android or ios fields that apply.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `platform` | enumeration; required; one of `android`, `ios` | |
| `target` | string; default `"lib/main.dart"` | |
| `buildName` | string; default `"1.0.0"` | |
| `buildNumber` | string; default `"1"` | |
| `flavor` | string | |
| `keystorePath` | string | |
| `keystorePassword` | string | |
| `keyAlias` | string | |
| `keyPassword` | string | |
| `gradleText` | string | Contents of android/app/build.gradle(.kts); checked for key.properties. |
| `teamId` | string | |
| `exportOptionsPlist` | string | |
| `noCodesign` | boolean; default `false` | |

```bash
game_agent release plan <platform>
```

REST: `POST /v1/release/plan` · MCP tool: `release.plan` · JSON-RPC method: `release.plan`

## save

### `save.decode`

Read a save text back into its JSON.

Fails with `validation_failed` and a player-readable message when the text is damaged or not a save code.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `code` | string; required | |

Errors: `validation_failed`.

```bash
game_agent save decode <code>
```

REST: `POST /v1/save/decode` · MCP tool: `save.decode` · JSON-RPC method: `save.decode`

### `save.encode`

Turn a save into the shareable text a player can copy (GSAVE1...).

The text carries the JSON in URL-safe base64 plus a checksum, so a typo is caught when it is imported.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `save` | object; required | |

```bash
game_agent save encode
```

REST: `POST /v1/save/encode` · MCP tool: `save.encode` · JSON-RPC method: `save.encode`

### `save.migrate`

Check that a save can be upgraded to a version, and stamp it.

Runs the registered migrations from the save\'s `saveVersion` (1 when absent) up to `toVersion`. The engine ships no migrations of its own, so this reports `validation_failed` for any gap and succeeds only for a save already at `toVersion`; games register theirs with `SaveMigrator`.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `save` | object; required | |
| `toVersion` | integer; required; 1 to ∞ | |

```bash
game_agent save migrate
```

REST: `POST /v1/save/migrate` · MCP tool: `save.migrate` · JSON-RPC method: `save.migrate`

## schema

### `schema.component`

Describe one component: fields, types, ranges, defaults and its JSON Schema.

Includes the default template, which is exactly what `level.add_entity` starts a component with.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `name` | string; required | |

Errors: `not_found`.

```bash
game_agent schema component <name>
```

REST: `POST /v1/schema/component` · MCP tool: `schema.component` · JSON-RPC method: `schema.component`

### `schema.components`

List every component the engine knows, with its field count.

Names usable in `level.add_entity` and `level.set_field`. `filter` keeps names containing that text.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `filter` | string | Case-insensitive substring of the name. |

```bash
game_agent schema components
```

REST: `POST /v1/schema/components` · MCP tool: `schema.components` · JSON-RPC method: `schema.components`

### `schema.idle_game`

JSON Schema for a whole `assets/idle_game.json` definition file.

Draft 2020-12 schema for the document [validateIdleDefinition] accepts. Component field schemas remain under `schema.component` (generator, upgrade, …).

*read*, idempotent.

```bash
game_agent schema idle-game
```

REST: `POST /v1/schema/idle_game` · MCP tool: `schema.idle_game` · JSON-RPC method: `schema.idle_game`

### `schema.template`

The default JSON of a component (every field at its default).

Start from this when building a component by hand.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `name` | string; required | |

```bash
game_agent schema template <name>
```

REST: `POST /v1/schema/template` · MCP tool: `schema.template` · JSON-RPC method: `schema.template`

### `schema.validate_component`

Check one component value against its schema without touching any file.

Runs the same validator as level validation on a one-entity level, so the answers agree with `level.validate`.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `name` | string; required | |
| `value` | json; required | |

```bash
game_agent schema validate-component <name>
```

REST: `POST /v1/schema/validate_component` · MCP tool: `schema.validate_component` · JSON-RPC method: `schema.validate_component`

## strategy

### `strategy.rules`

Describe the turn-based components, orders, systems and AI kinds the engine ships.

A static catalogue for agents authoring strategy levels or calling `strategy.simulate_turns`. Nothing is loaded or run.

*read*, idempotent.

```bash
game_agent strategy rules
```

REST: `POST /v1/strategy/rules` · MCP tool: `strategy.rules` · JSON-RPC method: `strategy.rules`

### `strategy.simulate_turns`

Run a headless turn-based skirmish for a few team-turns and return the event log.

Loads a level (`path` or inline `json`) with team/grid/AP/unitStats entities, wires `OrderSystem` + `AITurnSystem` + win/combat, and steps until `turns` team-turns have ended (or someone wins). `ai` selects AggressiveAI or TacticalAI for every team. Uses a TileMap navigator when the level has one; otherwise an open grid sized to the units. Deterministic for the same level + args. Nothing is written.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `path` | path | |
| `json` | json | |
| `turns` | integer; default `1` | How many team-turns (TurnEndedEvent) to run before stopping. |
| `ai` | enumeration; default `"aggressive"`; one of `aggressive`, `tactical` | |

Errors: `validation_failed`.

```bash
game_agent strategy simulate-turns <path>
```

REST: `POST /v1/strategy/simulate_turns` · MCP tool: `strategy.simulate_turns` · JSON-RPC method: `strategy.simulate_turns`

## undo

### `undo.list`

List recent writes that can be undone, newest first.

Reads the journal in `.studio/undo/`. Each entry has the operation, who did it, when and which files it touched.

*read*, needs an open project, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `limit` | integer; default `20`; 1 to 100 | |

```bash
game_agent undo list
```

REST: `POST /v1/undo/list` · MCP tool: `undo.list` · JSON-RPC method: `undo.list`

### `undo.redo`

Redo the newest undone write (or a given entry).

Re-applies a journal entry that was undone, if its files are still as the undo left them (or `force`).

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `id` | string | Entry id from undo.list; default the newest undone. |
| `force` | boolean; default `false` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `not_found`, `conflict`.

```bash
game_agent undo redo
```

REST: `POST /v1/undo/redo` · MCP tool: `undo.redo` · JSON-RPC method: `undo.redo`

### `undo.undo`

Undo the newest write (or a given entry) by restoring the files it changed.

Restores the files of a journal entry to their content before that write. It refuses if a file changed after the entry (so a later edit is not lost) unless `force` is true. An undone entry can be redone.

*write*, needs an open project.

| Parameter | Type | Description |
|---|---|---|
| `id` | string | Entry id from undo.list; default the newest not yet undone. |
| `force` | boolean; default `false` | |
| `apply` | boolean | Write now (default for write operations) or only preview (default for destructive ones). |
| `confirmation` | string | The token returned by the preview of a destructive operation; applies exactly that change. |

Errors: `not_found`, `conflict`.

```bash
game_agent undo undo
```

REST: `POST /v1/undo/undo` · MCP tool: `undo.undo` · JSON-RPC method: `undo.undo`

## world

### `world.build`

Load a level into a headless in-memory world and return its id.

Give `path` (a project level) or inline `json`. `systems` chooses what runs on each step (movement, collision, pushable, tileAnimation, tween, particles); default movement and collision. At most 4 worlds exist at once and an unused one expires after 10 minutes. Nothing is written.

*read*.

| Parameter | Type | Description |
|---|---|---|
| `path` | path | |
| `json` | json | |
| `systems` | array | Subset of: movement, collision, pushable, tileAnimation, tween, particles. |

Errors: `rate_limited`, `validation_failed`.

```bash
game_agent world build <path>
```

REST: `POST /v1/world/build` · MCP tool: `world.build` · JSON-RPC method: `world.build`

### `world.discard`

Drop a world from memory.

Frees a slot; unknown ids are `not_found`.

*read*.

| Parameter | Type | Description |
|---|---|---|
| `worldId` | string; required | |

```bash
game_agent world discard <worldId>
```

REST: `POST /v1/world/discard` · MCP tool: `world.discard` · JSON-RPC method: `world.discard`

### `world.patch`

Change entities in a world with a snapshot-shaped patch.

The same patch `World.applyPatch` takes: `{entities: [{id, components: {name: json}}]}`. Affects only the in-memory world.

*read*.

| Parameter | Type | Description |
|---|---|---|
| `worldId` | string; required | |
| `patch` | json; required | |

```bash
game_agent world patch <worldId>
```

REST: `POST /v1/world/patch` · MCP tool: `world.patch` · JSON-RPC method: `world.patch`

### `world.query`

Entities that have a component, optionally matching field values.

`where` is `{field: value}` compared for equality against the component JSON.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `worldId` | string; required | |
| `component` | string; required | |
| `where` | object | |

```bash
game_agent world query <worldId>
```

REST: `POST /v1/world/query` · MCP tool: `world.query` · JSON-RPC method: `world.query`

### `world.snapshot`

The world as plain JSON (tick, entities and their components).

`entities` limits the output to those entity ids.

*read*, idempotent.

| Parameter | Type | Description |
|---|---|---|
| `worldId` | string; required | |
| `entities` | array | |

```bash
game_agent world snapshot <worldId>
```

REST: `POST /v1/world/snapshot` · MCP tool: `world.snapshot` · JSON-RPC method: `world.snapshot`

### `world.step`

Advance a world by a number of fixed steps.

Each step is `dt` seconds (default 1/60). Returns the new tick and per-component entity counts.

*read*.

| Parameter | Type | Description |
|---|---|---|
| `worldId` | string; required | |
| `ticks` | integer; default `1`; 1 to 100000 | |
| `dt` | number; default `0.016666666666666666`; 0.0001 to 1 | |

```bash
game_agent world step <worldId>
```

REST: `POST /v1/world/step` · MCP tool: `world.step` · JSON-RPC method: `world.step`

''',

  'reference/cli.md': '''# CLI reference: `game_agent`

Install:

```bash
dart pub global activate --source git \\
  https://github.com/arashrasoulzadeh/agentic-game-engine.git \\
  --git-path packages/engine_cli
```

Run `game_agent help <command>` any time; the tables below mirror that output.

| Command | One line |
|---|---|
| [`create`](#create) | Scaffold a new Flutter game |
| [`upgrade`](#upgrade) | Re-pin engine packages to a new git ref |
| [`lint`](#lint) | Validate a level JSON file |
| [`pack-assets`](#pack-assets) | Pack images into one atlas |
| [`build-release`](#build-release) | Signed Android AAB / iOS IPA |
| [`studio`](#studio) | Edit and validate level data from the command line |

## create

```bash
game_agent create my_game [--template strategy_game] [--org com.acme]
```

| Option | Default | Meaning |
|---|---|---|
| `--template` | `default_game` | `default_game` — a platformer starter. `strategy_game` — a turn-based skirmish against an AI (uses `engine_strategy`). `idle_game` — a playable idle/incremental game driven by `assets/idle_game.json` (uses `engine_idle`). |
| `--org` | `com.example` | Reverse-domain id for Android/iOS bundles. |
| `--output-dir` | `.` | Parent directory for the new project. |
| `--engine-repo` | this repo\'s URL | Git URL the generated `pubspec.yaml` depends on. |
| `--ref` | `main` | Git branch or tag to pin to. |

Project names must be `lower_snake_case`. The command refuses to overwrite an
existing directory.

## upgrade

Run inside a generated project:

```bash
game_agent upgrade --ref v0.2.0
```

Rewrites the `ref:` of every engine dependency it finds (`engine_core`,
`engine_flutter`, `engine_platformer`, `engine_strategy`, `engine_idle`) in `pubspec.yaml`,
then runs `flutter pub upgrade`. Only dependencies your project actually has
are touched.

## lint

```bash
game_agent lint assets/levels/main.level.json
game_agent lint level.json --render level.png --playable
```

| Option | Meaning |
|---|---|
| *(none)* | Validate the file against the content DSL. Exit 0 with a summary, or 1 with the exact error path (e.g. `entities[2].components["position"] must be an object`). |
| `--render <png>` | Also rasterize the `TileMap` (solid / one-way / slope colour-coded, entities as dots). Same preview as `level.lint` with `includeRender` (API returns base64). |
| `--[no-]playable` | Also flood-fill from the spawn entity and report anything unreachable. A conservative tile-connectivity heuristic, **not** a physics simulation. |

Great in CI, and for an agent to check a level it just wrote.

## pack-assets

```bash
game_agent pack-assets --input art/sprites --output-image assets/packed/atlas.png --scales 1.0,0.5
```

MaxRects bin-packs every image under `--input` into one sheet plus a region
manifest for `GameConfig.packedAtlasId`. Options: `--input/-i`,
`--output-image/-o`, `--output-manifest/-m`, `--padding` (default 2),
`--max-width` (default 2048, a hint not a cap), `--scales` (e.g.
`"1.0,0.5,0.25"` → `atlas@0.5x.png` …). Not run automatically by any build hook.

## build-release

```bash
game_agent build-release --android --keystore-path release.jks --keystore-password "\$KS_PASS" \\
    --key-alias upload --key-password "\$KEY_PASS"
game_agent build-release --no-android --ios --team-id ABCDE12345 --dry-run
```

| Option | Meaning |
|---|---|
| `-a/--[no-]android` | Build an AAB with `flutter build appbundle` (default on). |
| `-i/--[no-]ios` | Build an IPA with `flutter build ipa` (default off, macOS only). |
| `--build-name`, `--build-number` | Override the `pubspec.yaml` version. |
| `--keystore-path/-password`, `--key-alias/-password` | Android signing - all four, or none. |
| `--team-id` | iOS: generate an automatic-signing `ExportOptions.plist` for this team. |
| `--export-options-plist` | iOS: your own export options (needed for manual signing). |
| `--provisioning-profile`, `--codesign-identity` | Accepted, but an **error** without `--export-options-plist`: `flutter build ipa` has no such flags, so put them in the plist. |
| `--no-codesign` | Unsigned iOS build for testing. |
| `--[no-]split-per-abi` | Smaller per-ABI downloads. |
| `-f/--flavor`, `-t/--target`, `-d/--project-dir` | Flutter build selection. |
| `--[no-]dry-run`, `-v/--[no-]verbose` | Print instead of run / more output. |

Flutter has no `--keystore` flag, so Android signing works through `android/key.properties`: the command
writes it for the build (and deletes it afterwards, since it holds passwords) and **refuses to build
if the project\'s `android/app/build.gradle(.kts)` does not read it**, printing the snippet to add. Without that
refusal Flutter would sign with the debug key, which Google Play rejects. See [Releasing](../releasing.md).

!!! warning
    Passwords on the command line end up in shell history. Prefer environment
    variables (as above) or your CI\'s secret store.

## idle validate

```bash
game_agent idle validate assets/idle_game.json
```

Checks an idle game definition and prints every problem with its path (`generators[2].cost.growth must be a number >= 1`),
exit 1 if there are any; on success prints `OK` with the number of generators and upgrades. Run it after editing the JSON, in
CI, or from an agent.

## idle simulate

```bash
game_agent idle simulate assets/idle_game.json --days 2 --prestige-at 2
```

Plays an idle game definition with a deterministic greedy strategy (always buy the best payback, prestige any
layer when it pays `--prestige-at` times what you hold of that layer\'s currency, play incomplete challenges in
order) and prints when income passes each power of ten, each prestige, each challenge start/completion, each
achievement and the final income. Exits 1 on an invalid definition, printing every problem with its path. The
same input always prints the same report.

| Option | Default | Meaning |
|---|---|---|
| `--days` | `3` | Game time to simulate. |
| `--prestige-at` | never | Prestige a layer once its gain is at least this multiple of what is held. |
| `--play-challenges` / `--no-play-challenges` | on | Start and complete incomplete challenges. |

## studio

Scriptable level editing — the same operations the graphical studio performs,
so an agent can edit levels without opening a UI.

| Subcommand | Does |
|---|---|
| `validate` | Validate all levels in a project against the component schemas. |
| `add-entity` / `remove-entity` / `move-entity` | Entity edits (`add-entity` fills schema defaults). |
| `set-field` | Set one field of one component (creates the component if absent). |
| `set-layer` | Set an entity\'s draw-order `zIndex`. |
| `paint-tile` / `fill-region` | Edit a `tileMap` (tile id `0` erases). |
| `import-tmx` / `export-tmx` | Convert a Tiled `.tmx` map to a level file and back. |
| `save-prefab` / `place-prefab` | Save an entity as `prefabs/<name>.json`; place a prefab into a level. |
| `diff` | What differs between two level files, by entity and component (`--json`, `--exit-code`). |
| `lock` / `unlock` | Claim / release a level in a shared folder (advisory `<level>.lock`; exit 1 if someone else has it). |
| `merge` | Three-way merge `<base> <ours> <theirs>` by entity and component; exits 1 on conflict. |
| `export-levels` | Rewrite level files in canonical form (validated first). |
| `project-manifest` | Write or update `project.json`. |

### Merging level files in git

Level JSON merges badly line by line (a moved entity and an edited health bar collide on a line
neighbour). `studio merge` merges by entity and component instead, and writes the result over
**ours** the way a git merge driver must:

```gitattributes
# .gitattributes
*.level.json merge=level
```

```bash
git config merge.level.name "game_agent level merge"
git config merge.level.driver "game_agent studio merge %O %A %B"
```

Entities are matched by `name`; give the ones that matter a name. Where both sides changed the same
component differently, ours is kept and the exit code is 1, so git marks the file conflicted.
''',

  'reference/transports.md': '''# Calling operations (CLI · MCP · REST · JSON-RPC)

<!-- Generated by `dart run tool/gen_api_docs.dart --transports` in packages/engine_api. Do not edit. -->

Every non-Flutter operation is reachable four ways. Full parameter tables: [operations reference](operations.md). Walkthrough: [tutorial 6](../tutorials/06-agent-api.md).

## Example: `level.list`

List the project\'s level files with their entity count and lock state.

### CLI

```bash
game_agent level list
game_agent level list --json
```

### MCP (stdio or `POST /mcp`)

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "level.list",
    "arguments": {}
  }
}
```

### REST

```bash
curl -H "Authorization: Bearer \$TOKEN" -X POST http://127.0.0.1:7421/v1/level/list
```

### JSON-RPC

```bash
curl -H "Authorization: Bearer \$TOKEN" -H \'Content-Type: application/json\' -d \'{"jsonrpc":"2.0","id":1,"method":"level.list","params":{}}\' http://127.0.0.1:7421/rpc
```

## Catalogue size

This registry has **86** operations (83 served over MCP/HTTP; Flutter-only ones stay CLI-only).

''',

  'reference/cheatsheet.md': '''# Cheat sheet

One page of the calls you\'ll use most. Each section links to the full story.

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
world.systemOrder;                             // [\'orders\', \'turn\', …]
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
spawnEnemy(world, x: 400, y: 400, behaviorId: \'patrol\', maxHealth: 20);
installPlatformerSystems(world, player: player, behaviors: behaviors);
spawnHealthHudBar(world, source: player, x: 20, y: 20, width: 200, height: 20);
```

→ [Tutorial 1](../tutorials/01-hello-world.md) · [Platformer concepts](../concepts/platformer.md)

## Turn-based strategy in eight lines

```dart
final nav = GridNavigator(cols: 8, rows: 8, terrainCost: (c, r) => 1);
installStrategySystems(world, navigator: nav, cellSize: 48,
    aiTeams: {\'blue\': AggressiveAI()}, fog: false);
final u = spawnStrategyUnit(world, team: \'red\', col: 1, row: 6, cellSize: 48);
startTurnBasedGame(world, [\'red\', \'blue\']);       // after spawning
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
| Run an AI turn | pass `aiTeams: {\'blue\': MyAI()}` |

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
''',

};
