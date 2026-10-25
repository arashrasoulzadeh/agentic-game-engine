# Remaining work

The single source of truth for what is left. Check items off as they land
and delete them once shipped — what shipped is recorded in
[CHANGELOG.md](CHANGELOG.md), and the full reasoning is in git history.
Add new work here the moment you discover it rather than leaving it in a
comment or a side file.

Related, but not task lists:
- [docs/studio/design.md](docs/studio/design.md) — the studio's PRD,
  technical design, decisions, and the record of delivered phases (source
  comments cite its item numbers, e.g. "3.14", "IDE.13").
- [docs/concepts/turn-based-strategy.md](docs/concepts/turn-based-strategy.md)
  — how the finished turn-based layer works and why.

Sections: [Performance](#performance) ·
[Engine features](#engine-features) · [Operation registry and agent API](#operation-registry-and-agent-api-engine_mcpmd) · [Idle games](#idle--incremental-games) · [Turn-based strategy](#turn-based-strategy) ·
[Studio](#studio) · [Documentation](#documentation) · [Release](#release) ·
[Parked decisions](#parked-decisions)

## Performance

- [ ] GPU-shader shadow casting — **landed as opt-in engine
      infrastructure, but has a confirmed, unresolved real-device bug —
      NOT safe to enable, `test_game` does not use it.** Reported live
      (a real Android device showed fps dropping to ~24 with a
      flickering, shadow-casting torch in camera view). Researched how
      other engines handle 2D dynamic shadow casting at scale (a GPU-
      based 1D polar shadow map is the standard technique — a genuine
      ground-up rewrite with real cross-platform risk). Implemented a
      scoped-down variant instead: `Light2D.useGpuShadows` (`false`
      default) draws a GPU-shader point light
      (`shaders/light_shadow.frag`) doing per-pixel ray-vs-line-segment
      occlusion tests against nearby solid `TileMap` boundary edges,
      replacing the CPU `raycastTileMap` sweep for that light entirely.
      **What actually happened** (kept so the false leads aren't
      retraced): verified correct with a single light in a browser
      tool; wiring it into every `test_game` light produced an
      oversaturated white blob — first suspected (wrongly) as a stale
      dev-server artifact, since a fresh dev-server restart rendered
      correctly; shipped on that basis; then a real **release APK** (no
      dev server involved at all) reproduced the identical bug
      immediately and reliably, conclusively ruling out "just a stale
      dev server." Reverted `test_game`'s lights to `useGpuShadows:
      false` and confirmed via a fresh release-APK install that this
      restores correct rendering. **Root cause not yet confirmed on
      device, but a concrete, mechanistically-explained hypothesis now
      exists** (found via code review, not yet device-verified — no
      device was connected to test it, and this sandbox cannot even
      compile/bundle the shader to check via `flutter test`, confirmed
      by `gpu_light_shader_test.dart`'s own `markTestSkipped` path):
      `light_shadow.frag`'s `falloff(t)` is *flat at full strength
      (`1.0`) out to 60% of the light's radius* (`if (t <= 0.6) return
      1.0;`), and for an untinted light the shader's output alpha at
      that plateau is `uColor.a * strength` = `1.0 * intensity` — i.e.
      a **fully opaque white disc covering the inner 60% of every
      shadow-casting light's radius**, composited with unbounded
      `BlendMode.plus` (`src + dst`, clamped only *after* summing).
      Two such opaque plateaus overlapping — trivial for
      torches spaced for a readable corridor, e.g. this repo's own
      prison level — saturates that whole overlap region to solid
      white in one draw pair, before any third light even needs to
      contribute; every additional overlapping light only grows the
      saturated area. A single light's own opaque core is fine and
      expected (matches "verified correct with a single light"); the
      bug is this plateau being large (60% of radius, not just a small
      hot center) combined with `plus` having no ceiling across
      multiple draws — categorically different from "NaN uniforms" or
      "cone lights specifically," both already ruled out. This doesn't
      affect the CPU-path tint/overbright passes the same way despite
      also using `BlendMode.plus`, since those are driven by
      `colorArgb`'s alpha / `overbrightIntensity` — values a level
      author sets deliberately low for a subtle glow — not a hardcoded
      `1.0`.
      **Candidate fix now implemented, NOT YET VERIFIED**: the GPU pass
      in `EngineView._drawLighting` switched from `BlendMode.plus`
      (unbounded: `src + dst`, clamped only *after* summing) to
      `BlendMode.screen` (`src + dst - src*dst`, mathematically bounded
      — can never exceed full white regardless of how many lights'
      draws overlap). Zero risk to ship as-is: `useGpuShadows` still
      defaults `false` and `test_game` still doesn't enable it, so
      nothing live changed — this just means the fix is immediately
      testable the next time a device is available, instead of needing
      to be written first. **Still needs real-device confirmation
      before this bug is considered resolved** — "mathematically
      bounded" rules out this *specific* saturation mechanism but
      hasn't been checked against a real screenshot A/B or GPU frame
      capture yet, and this exact TODO item already has one false-lead
      history (the stale-dev-server misdiagnosis) worth not repeating
      by declaring victory early. If confirmed: flip `useGpuShadows` on
      in `test_game`'s torches, remove the "KNOWN BUG" language from
      `Light2D.useGpuShadows`'s doc comment, and check this item off.
      If NOT fixed: the shrink-the-`falloff`-plateau alternative
      (`light_shadow.frag`'s flat region below `1.0`, or shrinking the
      `t <= 0.6` range) is still on the table, and worth trying next
      rather than reverting to `plus`. The single-multi-light-shader-
      pass idea (one draw call for every light via uniform arrays) is
      still worth doing eventually for both performance and potentially
      fixing this by construction, but shouldn't be started until this
      is actually confirmed either way.

## Engine features

- [x] **Networking: beyond the WebSocket basics** (DECIDED: WebRTC and NAT traversal need a native plugin or a relay service, so
      the engine stops at the `NetEndpoint` contract: a game wires `flutter_webrtc` or a relay behind it) — host/client sessions, order
      validation, clock sync and a `dart:io` WebSocket transport exist (see the
      networking guide). A browser transport (`engine_core_web.dart`, `connectBrowserWebSocket`, verified end to end against the `dart:io`
      server from node) and `wss://` guidance are done. A UDP transport (`UdpListener`, `connectUdp`) is done. A room-list lobby (`LobbyServer`) is done. Still missing: WebRTC and NAT traversal / relaying. Host-side authentication (`HostSession(authenticate:)`) is done. The Flutter widget is done (`OnlineStrategyView` in `engine_strategy`).
- [x] **Example game** (DECIDED: the three `game_agent create` templates - platformer, strategy, idle - are the published
      samples and CI builds each; no sample app is committed, per CLAUDE.md) — one complete small game showing the major features,
      playable in the browser. (`test_game/` stays local and gitignored; this
      would be a separate, deliberately published sample — decide where it
      lives before starting, since CLAUDE.md forbids committing a sample app
      to this repo.)
- [ ] **For zahaak** — gameplay features the local-only `zahaak` game design
      needs but the engine lacks (see `zahaak/docs/engine-gap-analysis.md`).
      Not scoped; revisit once its combat/dialogue scope is locked.

## Operation registry and agent API (`engine_mcp.md`)

- [x] Phases 0-7: registry, safety pipeline, CLI binding, MCP/REST/JSON-RPC server, generated docs, e2e test (details in
      `engine_mcp.md`'s progress log).
- [x] Operations built: `project.*`, `level.*` (reads, writes, lint, TMX, merge, locks), `graph.*`, `prefab.*`, `asset.index` /
      `asset.atlas_regions`, `idle.*`, `save.*`, `world.*`, `schema.*`, `undo.*`, `release.plan`, `engine.*`.
- [x] Server hardening: token, Host check, limits, request log, CORS, idempotency keys, `engine_api.yaml`, project lock and
      `--allow-open`, no writes into `.studio`/`.git`.

**Adding an operation:** write it in `engine_core/lib/src/ops/groups/` (writes return a `Proposal`, never touch files), add it
to `all_operations.dart` and `engine_core_ops.dart`, test it in `engine_core/test/ops/`, then regenerate the reference with
`cd packages/engine_api && dart run tool/gen_api_docs.dart > ../../docs/reference/operations.md`. The CLI command, MCP tool,
REST route and JSON-RPC method appear on their own; the parity and docs-drift tests fail if anything is missed.

What is left:

- [ ] **Legacy `studio` edit commands as adapters of the `level.*` operations.** `studio_edit_commands.dart` (add/remove-entity,
      set-field, move-entity, set-layer, paint-tile, fill-region) still carries its own parsing, validation and direct file
      write beside the registry operations of the same name (which add undo, locks and structured errors). Make them thin
      adapters that keep the golden output of `studio_golden_test.dart`; behaviour changes (an undo entry per edit) need an
      owner decision first.
- [ ] **Operations not built yet:** `asset.pack` (`pack_assets_command.dart` has ~500 lines of private logic to extract into core), `i18n.*` (no project convention for locale files yet), `strategy.rules` /
      `strategy.simulate_turns` (the assembly lives in `engine_strategy`), `engine.docs`,
      `level.lint --render` as an operation (needs an injected image codec).
- [ ] **Server extras:** SSE streaming and progress notifications, cancellation (`notifications/cancelled`), `Retry-After`
      for the concurrency limit, request-log levels.

## Idle / incremental games

Everything planned in the former `TODO_IDLE.md` is shipped (what shipped is in [CHANGELOG.md](CHANGELOG.md); the guide is
`docs/concepts/idle-games.md`, the tutorial `docs/tutorials/05-idle-game.md`). Genre code lives in `engine_idle`; the
Flutter-free rules live in `engine_core` (`engine_core_idle.dart`).

- [x] **`engine_idle` package** — scaffold, CI, docs, schemas registered, template depends on it, studio picks up its schemas.
- [x] **Big numbers** — `BigNumber`, `BigTreasury` (strategy keeps the int `Treasury`, decided), `formatBigNumber` with suffix /
      scientific / engineering / grouped styles and locale separator.
- [x] **Time** — `OfflineProgress` (cap, efficiency, backwards clock), event-aware catch-up, deterministic bulk advance,
      clock-tampering policy, `OfflineSummary`, `IdleSession` lifecycle hooks.
- [x] **Rules layer** — generators, upgrades, cost curves (geometric, linear, table), multiplier stack, prestige (layers),
      achievements, taps and boosts, golden events, challenges, auto-buyer, `bestPurchase`.
- [x] **Saving** — `AtomicSave`, `SaveMigrator`, `SaveCodec` export/import, cloud-save hook.
- [x] **UI** — generator / upgrade lists, resource header, offline dialog, prestige, achievements, settings, challenge panel,
      memoised formatting.
- [x] **Background behaviour** — return notifications interface, offline-cap awareness, web lifecycle and storage.
- [x] **Tooling** — balance simulator (`game_agent idle simulate`), `idle validate`, schemas, `idle_game` template, docs.
- [x] **Cross-cutting** — determinism, anti-cheat position, analytics, accessibility, performance-budget test.
- [x] The balance simulator only auto-prestiges the first layer and does not play challenges.
- [ ] A real-device performance benchmark for 1,000 generators / long offline catch-up (the loose-budget test and host `benchmark/idle_bench.dart` exist; still needs timings from a release APK / real device).
- [ ] Keep a fixture save for every released version once there is one (`SaveMigrator`; harness + `save_v1.json` already exist).
- [x] Per-widget rebuild throttling beyond the controller's 10 Hz tick.

## Turn-based strategy

The turn-based layer is feature-complete for a first release (turn clock,
orders, grid navigation, combat, fog of war, selection, AI turns,
`engine_strategy`, `strategy_game` template). Left:

- [x] **Real-time strategy** — gathering, building, tech trees, builder units and per-unit body sizes (`GridFootprint`: blocking,
      turn-based and real-time routing via per-size flow fields, edge-to-edge attack reach) are all done.

## Studio

Design, decisions and delivered phases: [docs/studio/design.md](docs/studio/design.md).
Milestones M0–M2 (foundations, headless CLI, level-editor MVP) are done; the
code-editor phase is nearly done; the rest below is M2 distribution, M3–M5.

### Distribution (phase 3)

- [ ] **3.22 (remaining)** The `.dmg` script's packing step is verified (with a stand-in app), but a
      real `flutter build macos --release` failed here with Flutter's "does not contain
      architectures arm64 x86_64" check on `FlutterMacOS.framework` (it lists `x86_64 arm64`), so
      end-to-end packaging is unverified; `hdiutil create` is also deprecated in favour of
      `diskutil image create`. Also: `.msi` and `.AppImage` packaging, code signing and notarization for the
      `.dmg` (`engine_studio/tool/package_macos.sh` builds an unsigned one), and an actual release
      server / signing key: the client (bootstrap window, offline mode, update decisions) is done
      but has nothing to talk to yet.

### Code editor (phase 3B)

- [x] **IDE.11 true folding** — the gutter chevron collapses a block: its characters stay in the controller (so the saved file
      is untouched) but are painted at near-zero size with a tiny strut so their lines take no space, and the gutter
      skips their numbers. Any edit, or a caret entering hidden text, expands all folds.
- [ ] Not in the IDE scope yet (each its own phase): a debugger and a terminal. (Done: running `pub get` from the studio, and git
      status marks in the file tree; committing/diffing stays in the user's git tool.)


### Behaviors, profiling, polish (phase 6)

- [x] **6.2 / 6.3** The preview profiler shows step cost, entity count, a sparkline, the slowest systems and now the preview's own
      paint time (`PaintTimer`). Still not done: profiling a *separate* play-test process (no channel exists to build).
- [x] **Run game** — device choice (`flutter devices --machine` dialog), a stop button while the game runs, relaunch replaces the old process, and closing the editor stops it.
- [x] **6.6** Studio strings: every screen takes its text from `StudioStrings` (placeholders such as `{count}` supported), a key-existence
      guard and a placeholder-parity check protect the catalogs, and a Persian catalog ships (`locales/fa.json`). A few strings that carry
      their own widget keys/styles in the same call (the mode switch labels, toggle names) remain English.

### Stretch (not scheduled)

- [x] **7.1** Live reload of levels into a running game: done by file watching (`AssetHotReloader`, `ASSET_DIR` in the templates)
      rather than a socket; saving in the studio updates a game started with Run game.
- [x] **7.2** Visual diff in the studio: the "Show unsaved changes" button opens `LevelDiffView` (added / removed / per-field
      old → new). A visual three-way *merge* view is not built; `studio merge` and the git merge-driver recipe cover merging.
- [x] **7.3** Live refresh of another person's saved edits: the level editor watches its file (every 2 s in a project); a clean
      editor reloads and says so, one with unsaved edits shows a banner (Reload / Keep mine), its own saves are ignored and a
      half-written file waits. Presence is the advisory lock banner (who is editing, since when); a live cursor feed is
      not built.
- [x] **7.4** Embedded play-test: done by ADR 0005 (the Preview mode runs the edited level in the studio window; Run game starts
      the real game as a separate process).
- [x] **7.5** Plugin API: `StudioPlugin` / `StudioPlugins.register` adds graph node kinds (editing + validation) and custom
      inspector field editors (`'<component>.<field>'`), tested; compiling custom node kinds stays the game's job.

## Documentation

Site: <https://meetarash.ir/agentic-game-engine/> (MkDocs Material, built from
`docs/` by `.github/workflows/docs.yml`). Conventions:
[docs/contributing-docs.md](docs/contributing-docs.md).

### Coverage gaps — shipped features with no guide yet

None of these appear anywhere under `docs/` today. Each needs a concept page
(or a section) and, where it has runtime behaviour, a tested recipe:

- [x] `InvestigateBehavior.timeout` works: `HearingSystem` keeps an `age` on `lastHeardSound`, the behaviour forgets a sound older than the timeout.
- [x] Cinematics, scene transitions, video playback: all exist; guide `docs/concepts/cinematics.md` added, its cinematic
      samples run by `doc_examples_cinematics_test.dart` and its transition config by `doc_examples_transitions_test.dart`.
- [x] **Colorblind simulation** — `EngineView(colorblindMode:)` applies protanopia / deuteranopia / tritanopia as a colour
      matrix over the whole view (`colorblindMatrix`, tested); pass `PlayerOptions.colorblindMode`. The unused
      `ColorblindShader` / `colorblind.frag` were removed. Still open: whether `reduceMotion`, text scale etc.
      should be engine behaviour (the engine reads no `PlayerOptions` itself).
- [x] "Build your first level" studio tutorial (`docs/studio/first-level.md`; its command-line steps are run by
      `first_level_tutorial_test.dart`, the studio steps are not machine-checked).

### Quality of the docs themselves

- [x] **Versioned docs** — DECIDED: stay single-version until the first published release. The site deploys as a Pages
      artifact (not a `gh-pages` branch), which `mike` needs; switching is a one-time change to make together with the v0.1.0
      tag (see docs/engine-releasing.md), not before.
- [x] **Unpublished pages** — DECIDED: `studio/design.md` is published (Studio > Design and decisions); `proposals/` (drafts, not
      implemented) and `studio/qa-level-editor.md` (an internal QA checklist) stay excluded on purpose.
- [x] **Diagrams and screenshots** — real screenshots of the studio and the idle game, rendered by `screenshots_test.dart` in each
      package (`UPDATE_SCREENSHOTS=1 flutter test test/screenshots_test.dart` rewrites `docs/img/`). Still open: a strategy
      template screenshot (needs its art), and a studio picture with proper entity-label text.
- [x] **Executed-samples guarantee** — extended to ECS, cinematics, the multiplayer tutorial and the studio first-level steps;
      networking and real-time strategy samples are covered by their feature tests; the landing page says exactly what is
      not machine-checked (architecture, rendering widget snippets, studio click-through).
- [x] **README badges** — now live GitHub Actions status badges per package; swap for pub.dev version badges
      once published (see Release).

## Release

- [ ] Push the locally tagged `v0.1.0` (CHANGELOG says it exists only
      locally), and decide the tag / `ref` policy for generated projects.
- [ ] Publish the packages to pub.dev. That removes the self-referencing git
      dependency constraint documented in CLAUDE.md and `game_agent upgrade`'s
      `ref` matching limitation.
- [ ] Replace placeholder README badges with real ones after publishing.
- [x] Release/versioning checklist: `docs/engine-releasing.md`; `release_consistency_test.dart` enforces one shared
      version and `publish_to: none` on every package (this caught `engine_schema` missing it).

## Parked decisions

Not tasks — conclusions reached after analysis, kept so they aren't
re-litigated. Re-open only on the stated trigger.

- **No dirty-rect / partial redraw in `EngineView`.** `shouldRepaint` always
  returns `true`, so every tick re-runs the whole draw pipeline. Deliberate:
  a 2D game with a moving camera invalidates most of the screen every frame
  anyway, GPUs are fast at full-canvas redraws, and viewport culling already
  covers "don't do wasted work". Measured on a release APK on a real Android
  device (`SM S731B`, ~25 s of gameplay, ~24 sprites, ~45–50 particles, full
  lighting): `paint` costs 0.85–1.3 ms of an ~8.3 ms frame (~10–16%), with
  the lighting pass a further 0.1–0.3 ms. Not a bottleneck. **Re-open only**
  if a future scene profile shows `paint` itself becoming a real fraction of
  a frame that is actually over budget.
- **No 3D, ever** and **no other game engines** — see CLAUDE.md.
