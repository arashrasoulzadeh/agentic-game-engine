# Architecture

This is a reusable 2D game engine written in Dart. Flutter supplies the
application and rendering shell for Android, iOS, and Web. Games consume
the packages or are scaffolded with the `game_agent` CLI.

“Agent-friendly” means the engine exposes serializable world data,
data-authored levels, and a behavior/action API for controlling entities.
It does not by itself imply an integrated hosted AI model or service.

## Package boundaries

| Package | Responsibility | Internal dependencies |
| --- | --- | --- |
| [engine_core](packages/engine_core/README.md) | Entities, components, systems, world serialization, collision primitives, tile data, content loading, behavior API | None |
| [engine_flutter](packages/engine_flutter/README.md) | Game/scene lifecycle, rendering, camera, input, audio, save/load integration | `engine_core` |
| [engine_platformer](packages/engine_platformer/README.md) | Gravity, jumping, platform/tile resolution, combat, character helpers and animation | `engine_core`, `engine_flutter` |
| [engine_cli](packages/engine_cli/README.md) | Game scaffolding, dependency upgrades, content validation and asset packing | `engine_core` |

Core has no Flutter dependency. The shell must not depend on platformer
gameplay. For example, `TileMap` data lives in core so the shell can draw
it, while platformer tile collision logic lives in `engine_platformer`.

## Runtime flow

1. A game extends `Game`, supplies `GameConfig`, and returns its first
   `Scene` from `createInitialScene()`. `runGame` starts the Flutter shell.
2. `GameRunner` creates a fresh `World` for the scene and registers core
   and Flutter components. `Scene.populate` installs systems and entities;
   scene assets and camera are then prepared. Platformer content also needs
   its package's component registration.
3. The world stores component data by entity. Systems advance simulation
   in registration order. The Flutter view drives fixed simulation steps
   and interpolates rendering between them.
4. Input and AI feed gameplay. `AISystem` invokes registered `Behavior`s
   through `WorldView` and applies returned `Action`s. The API separates
   observation from action; it is not a process-isolation boundary for
   executing arbitrary untrusted Dart code.
5. The renderer reads world data to draw tiles, sprites, particles, text,
   and lighting through Flutter. Camera, audio, and persistence integrate
   with the application shell.
6. Scene switches create another world. `GameState` persists across scene
   changes; scene-local entities and systems belong to their own world.

For platformers, `installPlatformerSystems` provides the standard system
order. Grounding and collision must be resolved in the appropriate order
relative to jumping; manual reordering can change gameplay behavior.

## Content and extension points

`Level` loads data-authored content into a world. Component registries
associate component names with JSON decoders, supporting world
serialization, patching, and level loading. New built-in components need
registration and `toJson`/`fromJson` support in their owning package.

Extend gameplay with components, systems, helpers, and behaviors. Public
library exports and package READMEs describe the supported entry points;
files under `lib/src/` contain implementation details.

## Status and further reading

All package manifests currently declare version `0.1.0`. Follow
[TODO.md](TODO.md) for remaining work, especially rendering performance
and device validation of optional GPU shadows. See
[TODO_RENDER.md](TODO_RENDER.md) for rendering design discussions and
[CHANGELOG.md](CHANGELOG.md) for completed changes.

[CONTRIBUTING.md](CONTRIBUTING.md) covers setup and verification.
[AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md) cover repository working
conventions. Local `test_game/` content is ignored and is not part of the
distributed engine.
