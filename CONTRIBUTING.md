# Contributing

Start with [README.md](README.md) for the project overview,
[ARCHITECTURE.md](ARCHITECTURE.md) for package boundaries, and
[CLAUDE.md](CLAUDE.md) for the established engineering conventions.

## Local setup

Use a Flutter SDK that includes Dart compatible with `^3.9.0`, as required
by all four package manifests. There is no root `pubspec.yaml`; resolve
dependencies and run tools inside each package.

From the repository root:

```bash
(cd packages/engine_core && dart pub get)
(cd packages/engine_flutter && flutter pub get)
(cd packages/engine_platformer && flutter pub get)
(cd packages/engine_cli && dart pub get)
```

The checked-in `pubspec_overrides.yaml` files make the shell, platformer,
and CLI use sibling packages during local development. Preserve the Git
dependencies in `pubspec.yaml`: consumers need consistent repository refs.
Local overrides do not validate external Git dependency resolution.

The manifests currently use `v0.1.0` for the shell/platformer engine
dependencies and `main` for the CLI's core dependency. Check these files
before testing a generated game against a particular ref; do not assume
the older `main` examples describe every package's pin.

## Validation

Run these from the repository root for the packages affected by a change,
including downstream packages when a shared API changes:

```bash
(cd packages/engine_core && dart analyze --fatal-infos && dart test)
(cd packages/engine_flutter && flutter analyze --fatal-infos && flutter test)
(cd packages/engine_platformer && flutter analyze --fatal-infos && flutter test)
(cd packages/engine_cli && dart analyze --fatal-infos && dart test)
```

Format changed Dart files with `dart format`. Add regression tests for bug
fixes and behavioral tests for new features. For documentation-only edits,
check local links, examples against source, and `git diff --check`.
The workflows in [.github/workflows](.github/workflows) define the package
CI checks and their path filters.

For hot-path changes, also run the relevant benchmarks under
`packages/engine_core/benchmark/` and `packages/engine_platformer/benchmark/`.
For CLI or dependency changes, verify a generated game resolves dependencies
and builds against the intended published Git ref; local package tests alone
do not cover that integration. Publishing or pushing requires authorization.

## Trying the engine

Run the local CLI from its package directory:

```bash
cd packages/engine_cli
dart run bin/game_agent.dart --help
```

See [the CLI guide](packages/engine_cli/README.md) for `create`, `upgrade`,
`lint`, and `pack-assets`. Generated games are separate Flutter projects.
The ignored `test_game/` directory may exist in a developer checkout but
is not supplied by a fresh clone. Keep local sample games out of commits.

## Submitting changes

Keep changes focused, document public API changes in the relevant package
README, and update [CHANGELOG.md](CHANGELOG.md) for completed work.
Use [TODO.md](TODO.md) for remaining tasks and
[TODO_RENDER.md](TODO_RENDER.md) for parked rendering discussions.
Describe the problem, resulting behavior, and checks performed in a pull
request. Explain why a fix works and identify any unverified device behavior.
