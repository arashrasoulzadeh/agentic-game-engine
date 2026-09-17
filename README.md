# agentic-game-engine

[![engine_core](https://img.shields.io/badge/pub-engine__core%20v0.1.0-blue?logo=dart)](packages/engine_core)
[![engine_flutter](https://img.shields.io/badge/pub-engine__flutter%20v0.1.0-blue?logo=flutter)](packages/engine_flutter)
[![engine_platformer](https://img.shields.io/badge/pub-engine__platformer%20v0.1.0-blue?logo=dart)](packages/engine_platformer)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

> Badges above are placeholders (`v0.1.0`, pre-1.0, not yet published to
> pub.dev — see [API stability](#api-stability)). Once published, these
> should point at real pub.dev version badges instead of static text.

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

## Learn more: docs and tutorials

[`docs/`](docs/README.md) has a tutorial series and concept guides on
top of each package's API-reference README — written for both a human
developer and an AI coding agent to work from directly:

- [docs/getting-started.md](docs/getting-started.md) — install, scaffold, run, folder layout.
- [docs/concepts/](docs/concepts) — ECS, content-as-data, the agent API, rendering, platformer gameplay.
- [docs/tutorials/](docs/tutorials) — build a tiny real game step by step.
- [docs/examples/](docs/examples) — focused, copy-pasteable recipes.

## Why not Flame/Unity/Godot?

This engine exists for a specific thesis those don't optimize for:
**agent-drivable by design**. World state is plain JSON an agent can
read/patch (`World.toJson()`/`applyPatch()`), content is authored as
data rather than code (`Level`), and runtime NPC/agent logic is
sandboxed behind a read-only `WorldView` so a `Behavior` — hand-written
or LLM-backed — can never corrupt simulation state, only propose an
`Action` for the engine to apply. Flame is a fine general-purpose
Flutter game engine but doesn't share this design goal; Unity/Godot
aren't Dart/Flutter-native and don't run in this repo's
pure-simulation-core-plus-thin-shell shape. See
[docs/concepts/agent-api.md](docs/concepts/agent-api.md) for the
mechanism this actually produces.

## How a generated game is structured

`game_agent create` produces a normal Flutter project whose `main.dart`
extends `Game`, provides an initial `Scene`, and calls `runGame`.
The following sketch shows where world setup belongs:

```dart
class MyGame extends Game {
  @override
  GameConfig get config => _config; // orientation, world size, etc. — JSON

  @override
  Scene createInitialScene() => MainScene();
}

class MainScene extends Scene {
  @override
  Future<void> populate(
    World world, SceneController scenes, GameState state,
  ) async {
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

## API stability

Every package is pre-1.0 (`0.1.0`) today, so breaking changes can and
do happen freely — e.g. `resolveSolidCircleAabb` returning a
`CollisionSide` enum instead of a `bool`. Once a package reaches
`1.0.0`, it commits to normal semver: a breaking change to anything
exported from that package's top-level `<package>.dart` (`engine_core.dart`/
`engine_flutter.dart`/`engine_platformer.dart`/`engine_cli`'s public
API) requires a major version bump. Nothing under a package's internal
`lib/src/` makes that promise at any version — only the top-level
export surface is the contract; `src/` internals (including which
concern-folder a file lives in) can keep moving freely.

One deliberate, permanent exception carried into that commitment:
`engine_core`'s `Velocity`/`Action` and `engine_flutter`'s `Text`
collide with Flutter's own types of the same name. A consumer
importing both this engine and `material`/`widgets` resolves this with
`hide` on one side (`import 'package:flutter/material.dart' hide
Text;` or the reverse) — an established pattern, not a one-off
oversight (19 call sites across this repo already do it). Renaming these types to dodge
the collision was considered and rejected: it would be a bigger,
lower-value breaking change than the `hide` workaround it replaces,
which every consumer already has to reach for anyway when using any
Dart/Flutter package with a same-named type. This is staying as-is
through 1.0 and beyond.

## Development

Each package is tested independently:

```bash
(cd packages/engine_core && dart test && dart analyze --fatal-infos)
(cd packages/engine_flutter && flutter test && flutter analyze --fatal-infos)
(cd packages/engine_platformer && flutter test && flutter analyze --fatal-infos)
(cd packages/engine_cli && dart test && dart analyze --fatal-infos)
```

CI defines four package suites with path-based triggers — see
[.github/workflows](.github/workflows).

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and validation and
[ARCHITECTURE.md](ARCHITECTURE.md) for package boundaries and runtime flow.
AI agents should start with [AGENTS.md](AGENTS.md), which points to the
existing constraints and working conventions in [CLAUDE.md](CLAUDE.md).

## TODO: feature status

A snapshot summary — see [TODO.md](TODO.md) for the live, detailed
list and [CHANGELOG.md](CHANGELOG.md) for the full history behind
every item below.

### Done

**Core (`engine_core`)** — ECS (`World`/`ComponentStore`/systems),
spatial-hash collision, `TileMap` (+ `.tmx` import, slopes, ladders,
conveyors, per-tile friction, multi-layer/animated tiles, auto-tiling),
raycasting (tile + entity), A* pathfinding (binary-heap), deterministic
RNG + replay/record, content DSL (`Level`) + hot-reload
(`LevelHandle`), localization (`StringTable`), the agent-facing
`WorldView`/`Behavior`/`AISystem` sandbox, particle system, tweening,
triggers/pushables.

**Rendering (`engine_flutter`)** — sprite atlases + `Canvas.drawAtlas`
batching, z-index draw ordering, parallax backgrounds (tiled or
viewport-fit), 9-slice UI panels, text (single/multi-line, world- or
screen-space), 2D lighting (`Light2D`: soft falloff, color tint, real
shadow casting, cone/flashlight, flicker, day/night ambient cycle,
opt-in GPU-shader shadows), screen shake, cinematic camera, fixed-
timestep + render interpolation, on-screen debug overlay
(fps/tick/entity/sprite/particle counts, `showPerformanceOverlay`,
`FrameStats.onSpike`).

**Platformer (`engine_platformer`)** — gravity (+ asymmetric fast-
fall), jump (coyote time, buffering, double/wall jump, wall slide,
variable height, dash), tile/platform collision (incl. moving
platforms, one-way, slopes), ledge grab/mantle, water/swimming
physics, patrol/follow/avoidance AI, melee + ranged combat (`Weapon`/
`AttackSystem`, `Projectile`), health/damage/knockback/hitstun,
checkpoints + respawn, collectibles/inventory, boss-phase framework,
HUD bars, movement-driven + crossfaded animation.

**Input/audio/save** — keyboard + on-screen touch controls +
gamepad (button/axis bindings), remappable controls (persisted),
positional/spatial audio, pooled SFX playback, save/load with named
slots + schema versioning + migration.

**Tooling** — `game_agent` CLI (`create`/`upgrade`/`lint --render`/
`lint --playable`/`pack-assets` with MaxRects bin-packing + multi-
resolution `--scales`), a performance benchmark suite, 100% test
coverage across all four packages.

### Not done / in progress

- **`saveLayer`+`dstOut` ambient-lighting architecture** — works
  correctly today but costs an offscreen composite every frame a
  darkened scene renders; a shader-based single-pass rewrite would
  avoid that structurally but is real cross-platform risk, not
  started.
- **GPU-shader shadow casting (`Light2D.useGpuShadows`)** — real
  per-pixel-parallel shadows exist and are wired up, but a multi-light
  oversaturation bug is only candidate-fixed, not yet confirmed on a
  real device; stays off by default until it is.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup and validation,
and [CLAUDE.md](CLAUDE.md) for the established engineering conventions
(package DAG, no-unnecessary-comments, doc-comment/test requirements)
any change — human or AI-agent-authored — is expected to follow.

## License

MIT — see [LICENSE](LICENSE).
