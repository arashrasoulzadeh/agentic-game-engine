# CLI reference: `game_agent`

Install:

```bash
dart pub global activate --source git \
  https://github.com/arashrasoulzadeh/agentic-game-engine.git \
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
| `--template` | `default_game` | `default_game` — a platformer starter. `strategy_game` — a turn-based skirmish against an AI (uses `engine_strategy`). |
| `--org` | `com.example` | Reverse-domain id for Android/iOS bundles. |
| `--output-dir` | `.` | Parent directory for the new project. |
| `--engine-repo` | this repo's URL | Git URL the generated `pubspec.yaml` depends on. |
| `--ref` | `main` | Git branch or tag to pin to. |

Project names must be `lower_snake_case`. The command refuses to overwrite an
existing directory.

## upgrade

Run inside a generated project:

```bash
game_agent upgrade --ref v0.2.0
```

Rewrites the `ref:` of every engine dependency it finds (`engine_core`,
`engine_flutter`, `engine_platformer`, `engine_strategy`) in `pubspec.yaml`,
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
| `--render <png>` | Also rasterize the `TileMap` (solid / one-way / slope colour-coded, entities as dots). |
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
game_agent build-release --android --keystore-path release.jks --key-alias upload
game_agent build-release --no-android --ios --team-id ABCDE12345 --dry-run
```

| Option | Meaning |
|---|---|
| `-a/--[no-]android` | Build an AAB (default on). |
| `-i/--[no-]ios` | Build an IPA (default off, macOS only). |
| `--build-name`, `--build-number` | Override the `pubspec.yaml` version. |
| `--keystore-path/-password`, `--key-alias/-password` | Android signing. |
| `--team-id`, `--provisioning-profile`, `--codesign-identity`, `--export-options-plist` | iOS signing. |
| `--[no-]no-codesign` | Unsigned iOS build for testing. |
| `--[no-]split-per-abi` | Smaller per-ABI downloads. |
| `-f/--flavor`, `-t/--target`, `-d/--project-dir` | Flutter build selection. |
| `--[no-]dry-run`, `-v/--[no-]verbose` | Print instead of run / more output. |

!!! warning
    Passwords on the command line end up in shell history. Prefer environment
    variables or your CI's secret store.

## studio

Scriptable level editing — the same operations the graphical studio performs,
so an agent can edit levels without opening a UI.

| Subcommand | Does |
|---|---|
| `validate` | Validate all levels in a project against the component schemas. |
| `add-entity` / `remove-entity` / `move-entity` | Entity edits (`add-entity` fills schema defaults). |
| `set-field` | Set one field of one component (creates the component if absent). |
| `set-layer` | Set an entity's draw-order `zIndex`. |
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
