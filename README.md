# agentic-game-engine

A pure-Dart 2D game engine for building platformers (ECS, fixed-timestep
simulation, spatial-hash collision, tile-based and entity-based
platformer physics, patrol/follow AI, movement-driven animation) built
to be **AI-agent-friendly**: world state is plain, serializable data an
agent can read and patch, content is authored as data, and a sandboxed
`Behavior`/`WorldView` API lets an agent drive an entity at runtime
without any path to corrupting simulation state. Flutter is used only
as the cross-platform shell (rendering, input, audio, packaging) for
Android/iOS/Web — the simulation core has no Flutter dependency at all.

## Packages

| Package | What it is |
|---|---|
| [`packages/engine_core`](packages/engine_core/README.md) | The genre-general engine: ECS, `Position`/`Velocity`/`Collider`, spatial-hash collision, `TileMap` data, the content DSL, and the agent-facing `WorldView`/`Behavior` API. Pure Dart, zero Flutter imports. |
| [`packages/engine_flutter`](packages/engine_flutter/README.md) | The Flutter shell: `Game`/`GameRunner` app framework, sprite rendering, camera, input, audio, save/load. No gameplay logic. |
| [`packages/engine_platformer`](packages/engine_platformer/README.md) | 2D-platformer-genre gameplay: gravity, jump, tile/platform collision, player/enemy spawn helpers, patrol/follow AI behaviors, facing + movement-driven animation. Kept separate from `engine_core` so a non-platformer 2D game isn't forced to depend on gravity/jump concepts. |
| [`packages/engine_cli`](packages/engine_cli/README.md) | The `game_agent` CLI — scaffolds new Flutter games wired to the engine, updates their pinned version, lints content files. |

This repo is the **engine library**, not a game — there's no sample app
checked in (see [CLAUDE.md](CLAUDE.md) for why, and how `test_game/` is
used locally instead). Use the CLI (below) to generate one.

See each package's README for its full API. [TODO.md](TODO.md) tracks
what's left to build, and [CHANGELOG.md](CHANGELOG.md) tracks what's
already shipped.

## Quick start

Install the CLI:

```bash
dart pub global activate --source git https://github.com/arashrasoulzadeh/agentic-game-engine.git --git-path packages/engine_cli
```

Scaffold and run a game:

```bash
game_agent create my_game
cd my_game
flutter run
```

Update an existing game's engine version later:

```bash
game_agent upgrade --ref main
```

Validate a level/content file without running the game:

```bash
game_agent lint assets/level1.json
```

See [packages/engine_cli/README.md](packages/engine_cli/README.md) for
all CLI options.

## How a generated game is structured

`game_agent create` produces a normal Flutter project whose `main.dart`
extends `Game` and calls `runGame`:

```dart
class MyGame extends Game {
  @override
  GameConfig get config => _config; // orientation, world size, etc. — JSON

  @override
  void populateWorld(World world) {
    // World already built + core/Flutter components registered for you.
    world.addSystem(MovementSystem());
    world.storeOf<Position>().set(world.spawn(), Position(0, 0));
    // ...
  }
}
```

See [`packages/engine_flutter/README.md`](packages/engine_flutter/README.md)
for the full `Game` API (assets, camera, input, audio, save/load) and
[`packages/engine_core/README.md`](packages/engine_core/README.md) for
the ECS/physics/agent API underneath it.

## Development

Each package is tested independently:

```bash
cd packages/engine_core && dart test && dart analyze --fatal-infos
cd packages/engine_flutter && flutter test && flutter analyze --fatal-infos
cd packages/engine_cli && dart test && dart analyze --fatal-infos
```

CI runs all three suites separately on every push — see
[.github/workflows](.github/workflows).

Contributing to this repo (including as an AI agent)? Read
[CLAUDE.md](CLAUDE.md) first — it covers the non-obvious constraints
and working conventions this codebase relies on.
