# Idle / incremental games — what the engine still needs

The engine can already host a simple idle game: `Treasury` accrues fractional per-second income,
`Producer` / `Gatherer` / `Depot` model generators, tech trees gate unlocks, `WorldSnapshot` / `SaveGame`
persist everything, and the fixed timestep keeps results reproducible. This file lists what is missing
for a *real* idle game, in the order I would build it. The genre code lives in a new `engine_idle` package
(section 0); genre-general pieces go in `engine_core`. Same conventions as [TODO.md](TODO.md): check items
off when they land, delete them once shipped (what shipped goes in [CHANGELOG.md](CHANGELOG.md)), and add
new work here the moment it is discovered.

Nothing here is built yet. Each item says what "done" means, so it can be tested.

## 0. The `engine_idle` package

Idle-genre code gets its own package, the way strategy has `engine_strategy`. Create it first so every
later item has a home.

**Where things go** (the dependency rule in CLAUDE.md: genre-general *data* belongs in `engine_core`,
genre-specific *logic and UI* in the genre package; the one-way DAG is
`engine_core` → `engine_flutter` → `engine_idle`, and nothing depends backwards):

| Package | Gets |
|---|---|
| `engine_core` | `BigNumber`, number formatting, the big-number treasury, `OfflineProgress` and the bulk time advance, save versioning/migration, export/import, the multiplier stack and cost-curve maths (all genre-general, pure Dart, web-safe) |
| `engine_idle` | generator / upgrade / prestige / achievement components and systems, `installIdleSystems`, `spawnGenerator`-style helpers, the upgrade-list, resource-header, offline-summary, prestige and achievements widgets, notification scheduling interface |
| `engine_cli` | `game_agent idle simulate`, the `idle_game` template |
| `engine_schema` | schemas for the new components so `studio validate` and the inspector understand them |

**Package requirements.** Done: the package exists (`pubspec.yaml` with `publish_to: none` and the
self-referencing git dependencies, `pubspec_overrides.yaml`, `analysis_options.yaml`, `lib/engine_idle.dart`,
README, CHANGELOG, LICENSE, a smoke test), CI (`.github/workflows/engine_idle.yml`), the docs-workflow API loop,
and the package maps in `CLAUDE.md`, the root README and the architecture page. Still to do:

- [ ] Register each component in `registerIdleComponents` **with a schema** as it is added (currently registers
      nothing), keeping the "every registered component has a schema" test green.
- [ ] Tests mirroring `lib/`, doc comments explaining *why*, and a benchmark for hot paths
      (`packages/engine_idle/benchmark/`).
- [x] `engine_idle` is in the mkdocs nav (guide) and in the CLI / architecture docs; the release checklist item lives in [TODO.md](TODO.md).
- [x] `game_agent create --template idle_game` depends on it; `game_agent upgrade` must rewrite its `ref:` like the
      other engine dependencies (extend its list), and the template CI job must pass.
- [x] `engine_studio` palette / inspector pick up its schemas without code changes (`entity_palette_test.dart` places a `generator`).

## 1. Numbers that do not overflow

`Treasury.amounts` is `Map<String, int>`: 64-bit, so it overflows in a long incremental game, and the
fractional carry is a `double` that loses precision at large magnitudes.

- [ ] **Use `BigTreasury` in the strategy economy?** `BigTreasury` (`engine_core`) is the idle counterpart of
      `Treasury` and the old int `Treasury` is deliberately untouched, so existing saves keep loading. Decide
      whether `Producer` / gathering / construction should also accept it (they take `Treasury` today); idle
      games do not need them to.
- [ ] **Number formatting, remaining** — `formatBigNumber` (suffix / scientific / engineering, decimals, decimal
      separator, rounding carry) is done in `engine_core`. `IdleController.decimalSeparator` carries the locale's mark to every widget (the game sets it from its localisation). Left: reading
      `LocalizationManager` automatically, and group (thousands) separators for plain numbers.

## 2. Time: offline progress and catch-up

`Treasury.accrue(dt)` is correct for a large `dt`, but nothing records *when* the game was last running or
turns a long absence into progress.

- [ ] **Offline progress, remaining** (event-aware catch-up is done: `OfflineProgress.applyInSlices`, `IdleSession(whileAway:)`) — `OfflineProgress.catchUp` / `creditFor` / `untilCap` and the cap,
      efficiency, minimum-away and backwards-clock rules are done (`engine_core`). Left: a persisted
      `lastActiveAt` helper in the save, and **event-aware catch-up** for economies whose rates change while away
      (auto-buyers); today it assumes constant rates and the guide says so.
- [x] **Deterministic bulk advance** (`session_test.dart` proves 3600 one-second steps equal one `catchUp`; the economy is closed-form, so no `World.advance` is needed) — a `World.advance(Duration)` (or an economy-only fast-forward) that
      skips rendering and per-tick events but keeps the same results as stepping, so catch-up is
      reproducible. Done when: stepping N ticks and bulk-advancing the same time give equal treasuries.
- [x] **Clock-tampering policy** (documented in the guide's "Trust" section; `IdleSession(clock:)` is the server-time hook) — decide and document: trust the device clock (simple), or also keep a
      monotonic counter / server time. At minimum: never grant negative or absurd (> cap) time, and expose a
      hook for a server time source.
- [x] **"While you were away" model** (`OfflineSummary`) — a plain data object (time away, per-resource gains, anything that
      completed) the UI can render. Done when: it is produced by `OfflineProgress` and covered by tests; the
      screen itself is item 5.
- [ ] **App lifecycle hooks, remaining** — `IdleSession` (`save`, `load` with migration + catch-up, `onPause` / `onResume`,
      autosave, `exportCode` / `importCode`) and `IdleLifecycleHost` are done and tested. Left: web file-less store
      (a `SaveStore` over browser storage) and the "watch an ad for 2x" hook.

## 3. The idle-genre rules layer

The building blocks are there; the genre's *structure* is not.

- [ ] **Generator / upgrade data, remaining** — `Generator`, `Upgrade`, `IdleModifiers` components (JSON, schemas,
      registered by `registerIdleComponents`), `computeIncome`, `buyGenerator` (×1 / ×N / max, caps, tech locks),
      `buyUpgrade` and `IdleSystem` are done in `engine_idle`. `validateIdleDefinition` / `loadIdleDefinition` load a whole game from one JSON file with path-named errors
      (also done). Per-generator milestone bonuses (`milestones: [{owned, multiplier}]`) are done too.
- [ ] **Cost curves, remaining** — `GeometricCost`, `LinearCost` with closed-form `totalCost` / `maxAffordable`
      (verified against brute force) are done in `engine_core`. `TableCost` (hand-authored prices, optional tail growth) is done; the max-level cap is `Generator.maxOwned`.
- [ ] **Multiplier stack, remaining** — `ModifierStack` (additive + multiplicative, named sources, breakdown,
      order-independent) is done in `engine_core`; wire it to generators/upgrades/prestige in `engine_idle`.
- [ ] **Prestige, remaining** — `PrestigeRule`, `prestigeGainNow`, `performPrestige` (reset scope, permanent currency,
      `1 + bonusPerUnit * held` multiplier, lifetime stats kept) are done in `engine_idle`. Left: the prestige screen
      (section 5) and more reset-scope options (keep chosen generators).
- [ ] **Achievements, remaining** — `Achievement` data (`lifetime:` / `run:` / `owned:` / `prestiges` / `taps` / `seconds`
      stats, optional multiplier reward), `checkAchievements`, `AchievementUnlockedEvent` are done. Left: the
      achievements screen, and conditions on arbitrary events.
- [ ] **Active-play hooks, remaining** — `tapEarn` (multiplied, counted) and timed `Boost` / `BoostSystem` (restart refreshes,
      distinct boosts multiply) are done. Random "golden cookie" events (`GoldenEvents` + `GoldenEventSystem`, seeded RNG, `claimGolden`) are done too.

## 4. Saving

- [ ] **Autosave, remaining** — `AtomicSave` (temp file + rename, `.bak` of the previous save, corrupt-file fallback) is
      done in `engine_core_io`. Left: the periodic/on-pause trigger, which belongs to the lifecycle hooks.
- [ ] **Save versioning, remaining** — `SaveMigrator` (versioned steps, newer-save refusal, missing-step error) is done
      in `engine_core`. Left: keep a fixture save for every released version once there is one.
- [ ] **Export / import, remaining** — `SaveCodec` (`GSAVE1.<payload>.<checksum>`, clear errors) is done; the UI for
      copy/paste is in section 5.
- [ ] **Cloud save hook** — an interface only (platform-specific implementations belong to the game).

## 5. UI

The engine's UI is menu buttons and HUD bars; an idle game's screens are long scrolling lists. These can be
ordinary Flutter widgets reading the game state, shipped as a small package or a section of `engine_flutter`.

- [ ] **Upgrade list, remaining** — `GeneratorList` / `GeneratorRow` (×1/×10/×100/Max, affordable/locked states, lazy list
      tested with 300 rows, semantic labels) and `UpgradeList` are done in `engine_idle`. Left: milestone progress
      display and a golden test.
- [ ] **Resource header, remaining** — `ResourceHeader` and `IdleController` (10 Hz notifications, real-time clock, style
      switch) are done. Left: per-widget rebuild throttling beyond the controller's tick.
- [ ] **"While you were away" dialog, remaining** — `OfflineSummaryDialog` is done; the 2x hook (`onDouble` callback + `IdleSession.doubleOffline`) and lifecycle wiring are done too.
- [x] **Prestige screen** and **achievements screen** (`PrestigePanel` with confirmation, `AchievementList` with progress).
- [x] **Settings** — `IdleSettingsPanel` (number-format switch via `IdleController.setStyle`, offline-rules notice); the game adds its own accessibility toggles.
- [ ] **Large-number performance** — formatting is cached; rebuilds are limited to values that changed.

## 6. Background behaviour

An app cannot run while closed on iOS/Android; the standard solution is catch-up on resume plus reminders.

- [x] **Local notifications interface** (`ReturnNotifier`, `IdleSession(notifier:)` schedules on pause with `untilCap`, cancels on resume; the game wires the plugin) — "your generators are full" / "offline cap reached in 8 h" scheduled
      from the known cap time; the engine defines the interface and a testable scheduler, the game wires a
      platform plugin (kept out of `engine_core`).
- [x] **Offline-cap awareness** (`OfflineProgress.untilCap`, used by the session's reminder) — the economy exposes "time until the offline cap is reached" so the
      notification and the UI agree.
- [ ] **Web** — pause/resume via page visibility; documented limits (browsers throttle background tabs, so
      catch-up on focus is the only reliable behaviour).

## 7. Tooling and balance

- [ ] **Balance simulator, remaining** — `simulateIdle` and `dart run tool/simulate.dart` (milestones, stall reasons,
      deterministic) are done in `engine_idle`. Golden-output test (`test/golden/`) is done. Left: a `game_agent idle simulate` CLI command (`engine_cli` is pure Dart and
      `engine_idle` depends on Flutter, so the rules must first move to a Flutter-free package, e.g. `engine_core`).
- [ ] **Schema + studio support** — component schemas for the new data (generators, upgrades, prestige,
      achievements) so `studio validate` and the inspector understand them; `docs/reference/components.md`
      regenerates.
- [x] **Template** — `game_agent create --template idle_game`: a minimal working idle game (one resource,
      three generators, upgrades, prestige, offline progress) that passes the generated-project CI.
- [ ] **Docs** — a concept guide (`docs/concepts/idle-games.md`) and a tutorial ("a cookie clicker in an
      afternoon"), every sample executed by a test, per the repo's docs rule.

## 8. Cross-cutting

- [ ] **Determinism** — all of the above uses the seeded RNG and fixed timestep; no `DateTime.now()` inside
      simulation code (time enters only through `OfflineProgress` and is injectable for tests).
- [x] **Anti-cheat position** (documented: trust the device for single-player; server authority for competitive/IAP) — decide what is client-trusted. A single-player idle game can trust the
      clock and save; one with a leaderboard or purchases cannot. Write the decision down.
- [x] **Analytics** — `IdleAnalytics` sends `idle_purchase`, `idle_prestige`, `idle_offline_return` through
      `AnalyticsManager` (so `setConsent` applies) or a test sink; `IdleController(analytics:)` wires it.
- [ ] **Accessibility** — `reduceMotion` honoured by number-tick animations; high-contrast affordable /
      locked states; no information carried by colour alone.
- [x] **Performance budget** — 1,000 generators and a 6-month offline catch-up are guarded by a loose-budget test
      (`engine_idle/test/performance_budget_test.dart`); a real-device benchmark is still open.

## Suggested order

0. ~~Scaffold `engine_idle`~~ (done).
1. ~~`BigNumber` and number formatting~~ (done, in `engine_core`); `BigTreasury`, `OfflineProgress`, cost curves, multipliers, generator/upgrade components and buying done, saving, prestige, achievements and lifetime stats; taps and boosts, and the core widgets; lifecycle/session; next: prestige/achievements screens, notifications, simulator, template, guide.
2. `OfflineProgress` and deterministic bulk advance.
3. Generator / upgrade data, cost curves, multiplier stack, buy modes.
4. Save versioning, autosave, export/import.
5. Upgrade list and "while you were away" widgets.
6. Prestige, achievements, boosts.
7. Notifications, balance simulator, template, guide.
