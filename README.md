# agentic-game-engine

A pure-Dart 2D game engine (ECS, fixed-timestep simulation, spatial-hash
collision) built to be **AI-agent-friendly**: world state is plain,
serializable data an agent can read and patch, and systems are small,
composable, and independently inspectable. Flutter is used only as the
cross-platform shell (rendering, input, packaging) for Android/iOS/Web —
the simulation core has no Flutter dependency at all.

## Packages

| Package | What it is |
|---|---|
| [`packages/engine_core`](packages/engine_core) | The engine itself: entities, sparse-set component storage, systems, event bus, spatial-hash collision, JSON world snapshot/patch API. Pure Dart, zero Flutter imports. |
| [`packages/engine_cli`](packages/engine_cli) | The `game_agent` CLI — scaffolds new Flutter games wired to `engine_core` and updates their pinned engine version. |

This repo is the **engine library**, not a game — there's no sample app
checked in. Use the CLI (below) to generate one.

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

See [packages/engine_cli/README.md](packages/engine_cli/README.md) for
all CLI options.

## Development

Each package is tested independently:

```bash
cd packages/engine_core && dart test
cd packages/engine_cli && dart test
```

CI runs both suites separately on every push — see
[.github/workflows](.github/workflows).
