# 5 · An idle game in an afternoon

You will generate a cookie-clicker-style game, change its economy by editing one JSON file, check the pacing
without playing, and wire in the player-facing extras. No Dart is needed until the last step.

## 1. Generate it

```bash
game_agent create bakery --template idle_game
cd bakery
flutter run
```

You get a tap button, a list of generators and upgrades, a resource header, saving, and a "while you were away"
summary. The whole game is `assets/idle_game.json`.

## 2. Change the economy

Open `assets/idle_game.json`. Each generator has a price curve (`base` × `growth`^owned) and an output per
second. Add a new one after `mine`, and reward owning many of them with a milestone:

```json
{ "id": "factory", "name": "Factory",
  "cost": { "type": "geometric", "base": "130000", "growth": 1.15 },
  "output": { "coins": "260" },
  "milestones": [ { "owned": 25, "multiplier": "2" }, { "owned": 50, "multiplier": "2" } ] }
```

Prices can also be a hand-written table for the first few copies:
`{ "type": "table", "prices": ["10", "25", "60"], "tailGrowth": 1.2 }`.

Mistakes are reported with the path to them (`generators[4].cost.growth must be a number >= 1`) when the game
starts.

## 3. Check the pacing without playing

From a checkout of the engine, run the greedy balance simulator on your file:

```bash
cd packages/engine_idle
dart run tool/simulate.dart ../../path/to/bakery/assets/idle_game.json --days 2 --prestige-at 2
```

It prints when income passes each power of ten, when it prestiges, and whether the design stalls. The same run
is pinned as a golden file in the engine's tests, so you can do the same for your game: any change in pacing
becomes a visible diff.

## 4. Add the extras

- **Offline earnings:** set `"offline": { "capHours": 8, "efficiency": 0.5 }`. Show
  `OfflineSummaryDialog` on return, with `onDouble:` if you offer a rewarded ad.
- **Reminder:** give `IdleSession` a `ReturnNotifier` that talks to your notification plugin; it is scheduled
  for the moment the cap is reached.
- **Prestige and achievements:** add `PrestigePanel` and `AchievementList` to a tab.
- **Golden events:** add a `goldenEvents` component and `GoldenEventSystem(DeterministicRandom(seed))`.

Read the [idle games guide](../concepts/idle-games.md) for how each piece works.
