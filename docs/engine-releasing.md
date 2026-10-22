# Releasing the engine

(Releasing a *game* to the stores is a different guide: [Releasing to the stores](releasing.md).)

The engine ships as one unit. Every package under `packages/` has the same `version`, and every one has
`publish_to: none` until the pub.dev plan in `TODO.md` is carried out; `release_consistency_test.dart` in
`engine_core` enforces both, so adding a package (like `engine_idle`) without them fails CI.

## Checklist

1. All package workflows are green on `main` (core, flutter, platformer, strategy, idle, studio, cli, docs).
2. Bump `version:` in **every** `packages/*/pubspec.yaml` to the same value, and move the `[Unreleased]` entries
   in `CHANGELOG.md` under the new version.
3. Run the end-to-end check from `CLAUDE.md`: `game_agent create` for each template (`default_game`,
   `strategy_game`, `idle_game`) against the pushed repo, then analyze and test the generated project.
4. Tag `vX.Y.Z` and push the tag. Generated projects pin `ref: main` unless created with `--ref`; if the
   release should pin a tag, update every self-referencing `ref:` to it **in the same commit** (see the known
   limitation in `CLAUDE.md`).
5. When publishing to pub.dev starts: remove `publish_to: none` per package, publish in dependency order
   (`engine_schema`, `engine_core`, `engine_flutter`, then `engine_platformer`, `engine_strategy`,
   `engine_idle`, `engine_cli`), and replace the git dependencies with version constraints.

## Publishing readiness (checked)

`dart pub publish --dry-run` on `engine_schema` (with `publish_to: none` removed in a scratch copy) reports **0 warnings**: it
has a LICENSE, README, CHANGELOG and valid metadata. The other packages cannot dry-run yet only because their dependency on
`engine_schema`/`engine_core` is a git dependency; once those two are on pub.dev, replace the git blocks with
`^0.1.0` constraints and re-run the dry run in dependency order.
