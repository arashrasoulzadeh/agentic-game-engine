# Examples

Focused, copy-pasteable recipes. Each solves one problem and says what to
watch out for.

**How these are verified:** the *turn-based* recipes are executed by
`packages/engine_strategy/test/doc_examples_test.dart`; the others are checked
against current signatures by hand. This repo ships no runnable sample app on
purpose (see [CLAUDE.md](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/CLAUDE.md)) —
drop snippets into a `Scene.populate` in a project made by `game_agent create`.

## Turn-based strategy

| Recipe | You learn |
|---|---|
| [Write your own turn-based AI](custom-turn-ai.md) | `TurnAI`, fog-aware targeting, how turns end |
| [Fog of war with walls](fog-of-war.md) | `FogOfWar`, `blocksSight`, `canSee` |
| [Show where a unit can move](move-range-overlay.md) | `reachable`, painting an overlay |
| [Save and restore a game](save-restore-turn-game.md) | Snapshots, the `applyPatch` catch |

## Platformer

| Recipe | You learn |
|---|---|
| [Spawn an enemy with patrol AI](spawn-enemy-with-patrol-ai.md) | `spawnEnemy`, `PatrolBehavior` |
| [Add a health bar](health-bar.md) | `spawnHealthHudBar`, world- vs screen-space |
| [Custom Behavior](custom-behavior.md) | The `WorldView` → `Action` contract |

## Any genre

| Recipe | You learn |
|---|---|
| [Save / load](save-load.md) | Slots, versioning, migration |
