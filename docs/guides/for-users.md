# For game makers

You want to make a game with ZARVAN using the command line and the Studio,
and you may not want to write much Dart. This page is your map.

## What you can make

| Kind of game | Starter | First read |
|---|---|---|
| Platformer | `default_game` | [Tutorial 1](../tutorials/01-hello-world.md) |
| Top-down (four-direction movement, pickups) | `topdown_game` | [Getting started](../getting-started.md) |
| Turn-based strategy | `strategy_game` | [Tutorial 2](../tutorials/02-turn-based-strategy.md) |
| Idle / incremental | `idle_game` | [Tutorial 5](../tutorials/05-idle-game.md) |

## Your first five minutes

```bash
dart pub global activate --source git https://github.com/arashrasoulzadeh/zarvan.git --git-path packages/zarvan_cli
zarvan create my_game
cd my_game
flutter run
```

Full walkthrough: [Getting started](../getting-started.md).

## Tools you will use

| Tool | What for | Docs |
|---|---|---|
| `zarvan create` / `upgrade` | Scaffold a game, move its engine version forward | [CLI](../reference/cli.md) |
| `zarvan lint` | Check a level file before running the game | [CLI](../reference/cli.md#lint) |
| `zarvan pack-assets` | Pack images into one atlas | [CLI](../reference/cli.md#pack-assets) |
| `zarvan build-release` | Signed Android AAB / iOS IPA | [Releasing to the stores](../releasing.md) |
| ZARVAN Studio | Edit levels and content visually | [Studio user guide](../studio/user-guide.md) · [Build your first level](../studio/first-level.md) |

## Content is data

Levels, idle-game definitions and dialogue are JSON files you edit, not code
you compile. See [Content as data](../concepts/content-as-data.md),
[Dialogue](../concepts/dialogue.md), [Localization](../concepts/localization.md)
and [Settings and accessibility](../concepts/settings.md).

## When something breaks

[FAQ & troubleshooting](../faq.md), then the [Glossary](../reference/glossary.md)
if a word is unfamiliar. Run `zarvan project open .` and read `project.problems`
to see content problems in one list.
