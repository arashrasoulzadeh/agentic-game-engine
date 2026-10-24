# engine_idle

Idle / incremental games on top of [engine_core](../engine_core/README.md) and
[engine_flutter](../engine_flutter/README.md): generators, upgrades, prestige, achievements, offline progress and the
widgets that show them. A whole game is one JSON file (resources, generators, upgrades, achievements, prestige,
offline rules); you write Dart only for what is yours.

Start from the template (`game_agent create my_game --template idle_game`) or read the
[idle games guide](../../docs/concepts/idle-games.md) and the
[tutorial](../../docs/tutorials/05-idle-game.md). Status: [TODO.md](../../TODO.md).

## Where things live

The Flutter-free rules are in `engine_core` (`package:engine_core/engine_core_idle.dart`) so command-line tools can use
them: components, the economy (`computeIncome`, `buyGenerator`, `buyUpgrade`), prestige and achievements, golden
events, the data loader (`loadIdleDefinition`), the balance simulator (`simulateIdle`, also
`game_agent idle simulate`), `BigNumber`, offline progress, cost curves and save formats. This package re-exports all of
that and adds what needs Flutter:

| Piece | What it does |
|---|---|
| `IdleController` | Steps the world about ten times a second, notifies widgets, number format and locale mark |
| `IdleSession` | Saving, loading, offline catch-up, app lifecycle, export/import codes, cloud sync, return reminders |
| `FileSaveStore`, `BrowserSaveStore`, `MemorySaveStore`, `CloudSaveStore` | Where a save lives |
| Widgets | `ResourceHeader`, `GeneratorList`, `UpgradeList`, `OfflineSummaryDialog`, `PrestigePanel`, `AchievementList`, `IdleSettingsPanel`, `SaveCodePanel`, `IdleLifecycleHost` |
| `IdleAnalytics` | Purchase, prestige and return events through the consent-aware analytics manager |

```dart
final world = World(width: 10, height: 10);
registerCoreComponents(world);
final game = loadIdleDefinition(world, jsonDecode(await rootBundle.loadString('assets/idle_game.json')));
world..addSystem(IdleSystem())..addSystem(BoostSystem());

final controller = IdleController(world: world)..start();
final session = IdleSession(controller: controller, store: BrowserSaveStore(), offline: game.offline)
  ..load()
  ..startAutosave();
```

Tests: `flutter test`; hot-path costs: `dart run benchmark/idle_bench.dart`; pacing of a definition:
`dart run tool/simulate.dart example/cookie_clicker.json --days 2 --prestige-at 2`.
