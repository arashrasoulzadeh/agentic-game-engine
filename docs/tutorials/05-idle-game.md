# 5 · An idle game in an afternoon

You will generate a cookie-clicker-style game, change its economy by editing one JSON file, check the pacing
without playing, and wire in the player-facing extras. No Dart is needed until you opt into automation.

## 1. Generate it

![The finished game](../img/idle-game.png)

```bash
game_agent create bakery --template idle_game
cd bakery
flutter run
```

You get a tap button, generators and upgrades, resource header, golden offers, prestige and achievements,
challenges, saving, and a "while you were away" summary. The whole game is `assets/idle_game.json`.

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

Validate without launching the app:

```bash
game_agent idle validate assets/idle_game.json
```

Mistakes are reported with the path to them (`generators[4].cost.growth must be a number >= 1`).

## 3. Check the pacing without playing

```bash
game_agent idle simulate assets/idle_game.json --days 2 --prestige-at 2
```

It prints when income passes each power of ten, when it prestiges or clears challenges, and whether the design
stalls. The same simulator is pinned as a golden in the engine's tests, so any change in pacing becomes a
visible diff.

## 4. Extras already in the template

- **Offline earnings:** `"offline": { "capHours": 8, "efficiency": 0.5 }` — `OfflineSummaryDialog` on return.
- **Prestige and achievements:** Progress tab (`PrestigePanel`, `AchievementList`).
- **Challenges:** `"challenges"` in the JSON + `ChallengePanel` on Progress.
- **Golden offers:** `"golden"` block + `GoldenEventSystem` + `GoldenOffer` (tap quickly when it appears).
- **Save codes:** Settings tab (`SaveCodePanel`) to move a run between devices.

## 5. Opt-in: auto-buyer

Add to the JSON:

```json
"autoBuyer": { "intervalSeconds": 5, "maxPerRun": 10 }
```

In `lib/main.dart`, after `IdleSystem()`:

```dart
..addSystem(AutoBuySystem())
```

and pass `whileAway: runAutoBuyer` into `IdleSession` so offline catch-up also buys. Flip `AutoBuyer.enabled`
when the player unlocks automation.

Read the [idle games guide](../concepts/idle-games.md) for how each piece works (prestige layers, cloud save,
analytics, trust model).
