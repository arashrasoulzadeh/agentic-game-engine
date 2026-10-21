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
- [ ] Add `engine_idle` to the mkdocs nav once it has a guide, and to the release / versioning checklist beside
      the other packages (see [TODO.md](TODO.md)).
- [ ] `game_agent create --template idle_game` depends on it; `game_agent upgrade` must rewrite its `ref:` like the
      other engine dependencies (extend its list), and the template CI job must pass.
- [ ] `engine_studio` palette / inspector pick up its schemas without code changes (verify, and add a test).

## 1. Numbers that do not overflow

`Treasury.amounts` is `Map<String, int>`: 64-bit, so it overflows in a long incremental game, and the
fractional carry is a `double` that loses precision at large magnitudes.

- [ ] **Use `BigTreasury` in the strategy economy?** `BigTreasury` (`engine_core`) is the idle counterpart of
      `Treasury` and the old int `Treasury` is deliberately untouched, so existing saves keep loading. Decide
      whether `Producer` / gathering / construction should also accept it (they take `Treasury` today); idle
      games do not need them to.
- [ ] **Number formatting, remaining** — `formatBigNumber` (suffix / scientific / engineering, decimals, decimal
      separator, rounding carry) is done in `engine_core`. Left: wire the locale's separators through
      `LocalizationManager` automatically, and group (thousands) separators for plain numbers.

## 2. Time: offline progress and catch-up

`Treasury.accrue(dt)` is correct for a large `dt`, but nothing records *when* the game was last running or
turns a long absence into progress.

- [ ] **Offline progress, remaining** — `OfflineProgress.catchUp` / `creditFor` / `untilCap` and the cap,
      efficiency, minimum-away and backwards-clock rules are done (`engine_core`). Left: a persisted
      `lastActiveAt` helper in the save, and **event-aware catch-up** for economies whose rates change while away
      (auto-buyers); today it assumes constant rates and the guide says so.
- [ ] **Deterministic bulk advance** — a `World.advance(Duration)` (or an economy-only fast-forward) that
      skips rendering and per-tick events but keeps the same results as stepping, so catch-up is
      reproducible. Done when: stepping N ticks and bulk-advancing the same time give equal treasuries.
- [ ] **Clock-tampering policy** — decide and document: trust the device clock (simple), or also keep a
      monotonic counter / server time. At minimum: never grant negative or absurd (> cap) time, and expose a
      hook for a server time source.
- [ ] **"While you were away" model** — a plain data object (time away, per-resource gains, anything that
      completed) the UI can render. Done when: it is produced by `OfflineProgress` and covered by tests; the
      screen itself is item 5.
- [ ] **App lifecycle hooks** — save a timestamp on pause/detach and run catch-up on resume (the engine
      already has `onPause`/`onResume` for analytics; unify with the game loop). Done when: a widget test
      simulating pause → 2 h → resume shows the summary exactly once.

## 3. The idle-genre rules layer

The building blocks are there; the genre's *structure* is not.

- [ ] **Generator / upgrade data, remaining** — `Generator`, `Upgrade`, `IdleModifiers` components (JSON, schemas,
      registered by `registerIdleComponents`), `computeIncome`, `buyGenerator` (×1 / ×N / max, caps, tech locks),
      `buyUpgrade` and `IdleSystem` are done in `engine_idle`. Left: loading a whole game definition from one
      JSON file with validation errors that name the field, and per-generator milestone bonuses.
- [ ] **Cost curves, remaining** — `GeometricCost`, `LinearCost` with closed-form `totalCost` / `maxAffordable`
      (verified against brute force) are done in `engine_core`. Left: a table curve and a max-level cap.
- [ ] **Multiplier stack, remaining** — `ModifierStack` (additive + multiplicative, named sources, breakdown,
      order-independent) is done in `engine_core`; wire it to generators/upgrades/prestige in `engine_idle`.
- [ ] **Prestige / reset loops** — a `PrestigeSystem`: on reset, wipe a configurable set of resources and
      generators, convert progress into a persistent currency by a formula (for example
      `floor(sqrt(lifetimeEarnings / k))`), apply its bonus as a multiplier source, and keep a lifetime
      statistics record. Done when: tests cover reset scope, the formula at boundary values, repeated
      prestiges, and that prestige currency survives save/load.
- [ ] **Achievements** — declarative conditions over resources/stats/events ("own 100 of X", "earn 1e9
      total"), one-shot unlock events, optional rewards (a multiplier source). Done when: conditions are
      evaluated cheaply (not every entity every tick) and unlocks persist.
- [ ] **Active-play hooks** — click/tap income with its own multiplier, timed boosts (×2 for 30 min), and
      "golden cookie" style random events driven by the deterministic RNG.
- [ ] **Lifetime statistics** — total earned, total taps, time played, prestige count; used by achievements
      and prestige formulas, stored in the save.

## 4. Saving

- [ ] **Autosave** — periodic and on pause, atomic write (temp file then rename), keep one previous
      generation, and survive a crash mid-write. Done when: a test that kills the write halfway still loads
      the last good save.
- [ ] **Save versioning and migration** — a `saveVersion` and a chain of migrations so new fields or
      renamed generators never wipe players. Done when: fixtures for every released version load.
- [ ] **Export / import** — a compressed, checksummed save string the player can copy (also a recovery path
      for lost devices); rejects corrupted input with a clear message.
- [ ] **Cloud save hook** — an interface only (platform-specific implementations belong to the game).

## 5. UI

The engine's UI is menu buttons and HUD bars; an idle game's screens are long scrolling lists. These can be
ordinary Flutter widgets reading the game state, shipped as a small package or a section of `engine_flutter`.

- [ ] **Upgrade list widget** — a scrolling list of generators/upgrades: name, level, cost (formatted), output,
      progress to next milestone, buy buttons (1/10/100/max), affordable/locked states, and
      `Semantics` labels. Done when: widget tests cover scrolling 200 rows (virtualised), affordability
      updating as income ticks, and each buy mode.
- [ ] **Resource header** — current amounts and per-second rates with smooth updating (not rebuilding the
      whole tree each tick; throttle to ~10 Hz).
- [ ] **"While you were away" dialog** — renders the item-2 summary, with a "collect" button and an
      optional watch-ad-for-2× hook (an interface, not an ad SDK).
- [ ] **Prestige screen** and **achievements screen**.
- [ ] **Settings** — number-format style, offline-progress notice, and the existing accessibility options.
- [ ] **Large-number performance** — formatting is cached; rebuilds are limited to values that changed.

## 6. Background behaviour

An app cannot run while closed on iOS/Android; the standard solution is catch-up on resume plus reminders.

- [ ] **Local notifications interface** — "your generators are full" / "offline cap reached in 8 h" scheduled
      from the known cap time; the engine defines the interface and a testable scheduler, the game wires a
      platform plugin (kept out of `engine_core`).
- [ ] **Offline-cap awareness** — the economy exposes "time until the offline cap is reached" so the
      notification and the UI agree.
- [ ] **Web** — pause/resume via page visibility; documented limits (browsers throttle background tabs, so
      catch-up on focus is the only reliable behaviour).

## 7. Tooling and balance

- [ ] **Balance simulator** — a headless CLI (`game_agent idle simulate`) that runs a scripted buying
      strategy for N simulated days and prints the time to each milestone / prestige, so designers tune cost
      curves without playing. Done when: it is deterministic and covered by golden output.
- [ ] **Schema + studio support** — component schemas for the new data (generators, upgrades, prestige,
      achievements) so `studio validate` and the inspector understand them; `docs/reference/components.md`
      regenerates.
- [ ] **Template** — `game_agent create --template idle_game`: a minimal working idle game (one resource,
      three generators, upgrades, prestige, offline progress) that passes the generated-project CI.
- [ ] **Docs** — a concept guide (`docs/concepts/idle-games.md`) and a tutorial ("a cookie clicker in an
      afternoon"), every sample executed by a test, per the repo's docs rule.

## 8. Cross-cutting

- [ ] **Determinism** — all of the above uses the seeded RNG and fixed timestep; no `DateTime.now()` inside
      simulation code (time enters only through `OfflineProgress` and is injectable for tests).
- [ ] **Anti-cheat position** — decide what is client-trusted. A single-player idle game can trust the
      clock and save; one with a leaderboard or purchases cannot. Write the decision down.
- [ ] **Analytics** — standard events (`prestige`, `offline_return`, `purchase`) through `AnalyticsManager`,
      respecting `setConsent`.
- [ ] **Accessibility** — `reduceMotion` honoured by number-tick animations; high-contrast affordable /
      locked states; no information carried by colour alone.
- [ ] **Performance budget** — 1,000 generators and a 6-month offline catch-up each stay under a stated time
      on a mid-range phone; a benchmark in `packages/engine_core/benchmark/` guards it.

## Suggested order

0. ~~Scaffold `engine_idle`~~ (done).
1. ~~`BigNumber` and number formatting~~ (done, in `engine_core`); `BigTreasury`, `OfflineProgress`, cost curves, multipliers, generator/upgrade components and buying done; next: save versioning, then the widgets, then prestige/achievements.
2. `OfflineProgress` and deterministic bulk advance.
3. Generator / upgrade data, cost curves, multiplier stack, buy modes.
4. Save versioning, autosave, export/import.
5. Upgrade list and "while you were away" widgets.
6. Prestige, achievements, boosts.
7. Notifications, balance simulator, template, guide.
