# Tutorial: a tiny platformer

Builds up a minimal but real game — a player, solid ground, one patrol
enemy, one collectible, a health bar — using only public API. Follow
[getting-started.md](../getting-started.md) first to scaffold and run
`my_game`; this tutorial edits `lib/main.dart`.

Every snippet below is checked against current signatures in
`packages/engine_core/lib/src/` and `packages/engine_platformer/lib/src/`.

## Step 1 — a `Game` and a `Scene`

```dart
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';

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
`Scene` explicitly — `Scene.populate` doesn't receive it implicitly,
so pass `input.state` (an `InputState`) into your `Scene`'s
constructor, the same pattern `spawnPlayer` expects (`input:` takes an
`InputState`, not the `InputController` itself).

## Step 2 — register platformer components and spawn the player

```dart
class MainScene extends Scene {
  MainScene(this.input);
  final InputState input;
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
      input: input,
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
attack systems in the one order that's actually correct — see
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
`packages/engine_core/README.md`'s `TileMap` section before authoring a
real level; the sketch above only uses the minimum for one solid floor.

## Step 4 — one patrol enemy

```dart
behaviors.register('patrol', PatrolBehavior(minX: 300, maxX: 500, speed: 60));

final enemy = spawnEnemy(
  world,
  x: 400, y: 400,
  behaviorId: 'patrol',
  affectedByGravity: true,
  maxHealth: 20,
);
```

`spawnEnemy` attaches `AIState('patrol')`, so `AISystem` (already
wired by `installPlatformerSystems` since `behaviors` was passed)
drives it via the registered `PatrolBehavior` every tick — see
[concepts/agent-api.md](../concepts/agent-api.md) for how that decision
loop works.

## Step 5 — a health bar

```dart
spawnHealthHudBar(world, source: player, x: 20, y: 20, width: 200, height: 20);
```

`HealthHudSystem` (already included in `installPlatformerSystems`)
keeps this bar's `HudBar.value`/`maxValue` synced from the player's
`Health` every tick — nothing else to wire up.

## Step 6 — one collectible

```dart
final coinId = world.spawn();
world.storeOf<Position>().set(coinId, const Position(450, 380));
world.storeOf<Collider>().set(coinId, const Collider(8));
world.storeOf<Sprite>().set(coinId, Sprite('items', 'coin')); // if you have an atlas loaded

world.storeOf<Inventory>().set(player, Inventory({'coin': 0}));
dealPickupOnTouch(world, {coinId}, 'coin');
```

`dealPickupOnTouch` wires a collision listener that calls
`collectItem` (adds to the player's `Inventory`, emits
`ItemCollectedEvent`) and destroys the coin entity by default.

## Step 7 — combat (optional)

Give the enemy a `Weapon` or let the player attack it — see
[concepts/platformer.md](../concepts/platformer.md)'s Combat section
and `packages/engine_platformer/README.md` for `Weapon`/`AttackSystem`
setup; it's deliberately left out of this base tutorial to keep it
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

- [examples/](../examples/) — smaller focused recipes (save/load, custom Behavior, more).
- [concepts/](../concepts/) — the underlying model for everything used above.
