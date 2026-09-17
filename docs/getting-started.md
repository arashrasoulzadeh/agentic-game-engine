# Getting started

## Prerequisites

- Flutter SDK with a Dart version satisfying `^3.9.0` (all four
  packages require this — check `flutter --version`).
- Git (the CLI pins generated projects to this repo via a git
  dependency, not a pub.dev version — see [Why a git dependency?](#why-a-git-dependency) below).

## 1. Install the `game_agent` CLI

```bash
dart pub global activate --source git \
  https://github.com/arashrasoulzadeh/agentic-game-engine.git \
  --git-path packages/engine_cli
```

This makes the `game_agent` command available on your `PATH` (Dart's
global pub cache `bin/` directory must be on it — `dart pub global
activate` prints a warning with instructions if it isn't).

## 2. Scaffold a project

```bash
game_agent create my_game
cd my_game
```

This produces a normal Flutter project pre-wired to the engine: a
`main.dart` with a `Game` subclass and an initial `Scene`, a
`pubspec.yaml` with the three engine packages as self-referencing git
dependencies (see below), and a starter `assets/` folder.

## 3. Run it

```bash
flutter run
```

Standard Flutter run — pick a connected device/emulator or a browser
target (`flutter run -d chrome`) the same way you would for any
Flutter app.

## 4. Folder layout

```
my_game/
  lib/
    main.dart        # Game subclass, createInitialScene(), runGame()
  assets/
    ...               # level JSON, sprite atlases, audio — content as data
  pubspec.yaml        # engine_core/engine_flutter/engine_platformer as git deps
```

`main.dart`'s shape, sketched:

```dart
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text; // Flutter's Text collides
import 'package:flutter/material.dart';

class MyGame extends Game {
  @override
  GameConfig get config => const GameConfig(worldWidth: 800, worldHeight: 600);

  @override
  Scene createInitialScene() => MainScene();
}

class MainScene extends Scene {
  @override
  Future<void> populate(
    World world, SceneController scenes, GameState state,
  ) async {
    // registerCoreComponents/registerFlutterComponents are already
    // called for you by GameRunner before populate runs.
    world.addSystem(MovementSystem());
    final player = world.spawn();
    world.storeOf<Position>().set(player, const Position(100, 100));
    world.storeOf<Velocity>().set(player, const Velocity(0, 0));
  }
}

void main() => runGame(MyGame());
```

See [`packages/engine_flutter/README.md`](../packages/engine_flutter/README.md)
for the full `Game`/`Scene`/`GameRunner` API, and
[concepts/ecs.md](concepts/ecs.md) for what `World`/`spawn`/`storeOf`
actually do.

## 5. Update the engine version later

```bash
game_agent upgrade --ref main
```

Rewrites the pinned git `ref` in your project's `pubspec.yaml` for all
three engine dependencies, then you run `flutter pub get` yourself.

## 6. Validate content without running the game

```bash
game_agent lint assets/level1.json
```

Checks a level/content JSON file against the `Level` DSL's validation
rules (see [concepts/content-as-data.md](concepts/content-as-data.md))
without booting a `Game`. See
[`packages/engine_cli/README.md`](../packages/engine_cli/README.md) for
`--render`/`--playable` flags.

## Why a git dependency?

None of these packages are published to pub.dev yet (pre-1.0, see the
root README's "API stability" section), so `game_agent create` wires
your project to `engine_core`/`engine_flutter`/`engine_platformer` via
a **self-referencing git dependency** (same repo URL, pinned `ref`) —
not a local `path:` dependency. Don't hand-edit those entries to
`path:` deps; see [CLAUDE.md](../CLAUDE.md)'s "Non-obvious constraints"
section for exactly why that breaks pub's dependency resolution across
a multi-package monorepo. Use `game_agent upgrade` to move the pin
forward instead of editing it by hand.

## Next

- [concepts/ecs.md](concepts/ecs.md) — the World/Entity/Component/System model.
- [tutorials/01-hello-world.md](tutorials/01-hello-world.md) — build something real, step by step.
