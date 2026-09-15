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
