# Repository guide for agents

Read [CLAUDE.md](CLAUDE.md) for the existing project constraints and
engineering conventions before changing code. Read [TODO.md](TODO.md)
for remaining work; a documentation task does not authorize working
through that backlog or committing/pushing changes.

## Project

This repository contains a Dart 2D game engine and Flutter shell, split
into four packages. See [ARCHITECTURE.md](ARCHITECTURE.md) for boundaries
and runtime flow and [CONTRIBUTING.md](CONTRIBUTING.md) for local setup
and validation commands.

## Working rules

- Keep `engine_core` free of Flutter. Put genre-specific gameplay in
  `engine_platformer`, and rendering/input/audio integration in `engine_flutter`.
- Preserve the package dependency direction. Shared data needed by the
  renderer belongs in core, even when platformer systems use it.
- Keep the engine 2D and built without another game engine.
- Keep `test_game/` and `examples/` local and ignored; do not commit a sample app.
- Preserve self-referencing Git dependencies in package manifests. Use
  `pubspec_overrides.yaml` for local development; inspect actual manifest
  refs before diagnosing dependency resolution, since prose can become stale.
- Register new serializable components in the appropriate package registry,
  provide JSON conversion and public API documentation, and test behavior.
- Check system ordering when changing simulation code. Prefer the existing
  `installPlatformerSystems` helper for the standard platformer pipeline.
- Preserve unrelated working-tree changes. Report validation actually run
  and any checks that could not be completed.

Package READMEs document APIs. Keep changes to those docs alongside API
changes, record shipped changes in [CHANGELOG.md](CHANGELOG.md), and keep
remaining work in the existing TODO files instead of creating duplicate lists.
