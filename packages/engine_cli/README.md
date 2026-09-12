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
