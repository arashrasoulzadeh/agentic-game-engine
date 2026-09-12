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
