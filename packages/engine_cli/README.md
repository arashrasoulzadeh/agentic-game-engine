# engine_cli

CLI for scaffolding and updating Flutter games built on `engine_core`.

## Install

```bash
dart pub global activate --source git https://github.com/arashrasoulzadeh/agentic-game-engine.git --git-path packages/engine_cli
```

## Create a new game

```bash
game_agent create my_game
cd my_game
flutter run
```

Options: `--org com.yourcompany`, `--output-dir path/to/parent`, `--ref <branch-or-tag>` to pin `engine_core` to something other than `main`.

## Update an existing game's engine version

Run from inside a project created by `game_agent create`:

```bash
game_agent upgrade --ref main
```

## Lint a level/content file

Validates a JSON file against the content DSL (`Level.validate` in
`engine_core`) without running the game — useful in CI or for an
agent to check a level file it just authored:

```bash
game_agent lint assets/level1.json
```

Exits 0 with a summary on success, or 1 with the specific error (e.g.
`entities[2].components["position"] must be an object`) on failure.

Add `--render <path.png>` to also rasterize the level's `TileMap` (solid/
one-way/slope tiles color-coded, entities marked as dots) so a human or
an agent can see the level's shape without running the game.

Add `--playable` to flood-fill the level's non-solid tiles from its
spawn entity (a positioned entity named with "player" or "spawn" in
it) and report any other entity that isn't reachable — catches a
level authoring mistake like an item or exit accidentally sealed off
behind solid tiles. This is tile connectivity, not physics: it can't
tell a gap too wide to jump from one that's crossable, so it's not a
substitute for actual playtesting.

## Pack sprite sheets

Packs every image under a directory into one sprite sheet + region
manifest (`GameConfig.packedAtlasId`'s expected input), using a
MaxRects bin-packing algorithm:

```bash
game_agent pack-assets --input art/sprites --output-image assets/packed/atlas.png
```

- `--input`/`-i` — directory to scan recursively for `.png`/`.jpg`/`.jpeg`/`.bmp`/`.gif` images.
- `--output-image`/`-o` — where to write the packed PNG (default `assets/packed/atlas.png`).
- `--output-manifest`/`-m` — where to write the region JSON (defaults to `--output-image` with a `.json` extension).
- `--padding` — transparent pixels between packed regions, to avoid texture-filtering bleed (default `2`).
- `--max-width` — starting width hint for the packer; it grows the sheet if needed, this isn't a hard cap (default `2048`).
- `--scales` — comma-separated resolution tiers, e.g. `"1.0,0.5,0.25"`, each packed to its own sheet+manifest pair with an `@<scale>x` suffix (e.g. `atlas@0.5x.png`) for a mobile game to load a smaller sheet at lower screen density instead of always paying full source-resolution texture memory. Picking which tier to load at runtime is the consuming game's decision, not this command's.

Run this before `flutter run`/`flutter build` whenever your source
sprite images change — it isn't run automatically by any build hook.
