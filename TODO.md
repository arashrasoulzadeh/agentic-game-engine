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
[Engine features](#engine-features) · [Turn-based strategy](#turn-based-strategy) ·
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

- [ ] **Networking: beyond the WebSocket basics** — host/client sessions, order
      validation, clock sync and a `dart:io` WebSocket transport exist (see the
      networking guide). Still missing: a browser transport (`NetEndpoint` over
      `web_socket_channel`), UDP/WebRTC for lower latency, a matchmaking/lobby
      service with NAT traversal, authentication and `wss://` guidance, interest
      management (send each player only what they can see), and a Flutter widget
      that connects, shows the mirror in `EngineView` and sends tap orders.
- [ ] **Example game** — one complete small game showing the major features,
      playable in the browser. (`test_game/` stays local and gitignored; this
      would be a separate, deliberately published sample — decide where it
      lives before starting, since CLAUDE.md forbids committing a sample app
      to this repo.)
- [ ] **For zahaak** — gameplay features the local-only `zahaak` game design
      needs but the engine lacks (see `zahaak/docs/engine-gap-analysis.md`).
      Not scoped; revisit once its combat/dialogue scope is locked.

## Turn-based strategy

The turn-based layer is feature-complete for a first release (turn clock,
orders, grid navigation, combat, fog of war, selection, AI turns,
`engine_strategy`, `strategy_game` template). Left:

- [ ] **Real-time strategy: gathering and building** — movement, combat, fog,
      flow fields, formations, smooth motion, a real-time AI driver and
      income/production all work (see the concept guide). Missing: units that
      gather a resource node and carry it home, placing buildings, per-unit
      collision radii larger than one cell, and tech trees.

## Studio

Design, decisions and delivered phases: [docs/studio/design.md](docs/studio/design.md).
Milestones M0–M2 (foundations, headless CLI, level-editor MVP) are done; the
code-editor phase is nearly done; the rest below is M2 distribution, M3–M5.

### Distribution (phase 3)

- [ ] **3.18** Bootstrap window: lists required downloads, shows progress,
      size and checksum result per item; retry on failure (design §2.13).
- [ ] **3.20** Update notices: the bootstrap window lists version changes with
      per-item accept/defer/skip; nothing installs without confirmation.
- [ ] **3.21** Offline mode: previously cached versions open existing projects
      when the manifest server is unreachable; test with a fake unreachable
      server.
- [ ] **3.22** Packaging scripts for `.dmg` first; `.msi` and `.AppImage`
      added once the macOS flow is verified end to end.

### Code editor (phase 3B)

- [ ] **IDE.11 (true folding)** — the data layer (`DartSession.foldingRanges`)
      and a gutter fold indicator exist, but the indicator selects-and-reveals
      a block instead of collapsing it: a `TextField` always renders its
      controller's full text, and that text is the saved file, so hiding
      lines would silently delete them on save. Real folding needs a custom
      rendering widget replacing `TextField` — a separate, larger piece of
      work.
- [ ] Not in the IDE scope yet (each its own phase): a debugger, a terminal,
      git integration, running `pub get` from the studio.


### Behaviors, profiling, polish (phase 6)

- [ ] **6.2 / 6.3** Studio profiler panel: show `WorldProfiler.report()`,
      `FrameStats` history and `FrameTimingMonitor` data from a running
      play-test (the engine side is done: `world.profiler`, `DebugOverlay`).
      Needs a channel from the play-test process to the studio.
- [ ] **6.6** (remaining) Move the rest of the studio's strings to `StudioStrings`
      (the mechanism and the project window are done; level, graph, code and
      inspector screens still hold English literals) and ship a first non-English
      catalog.

### Stretch (not scheduled)

- [ ] **7.1** Live reload of levels into a running game over a local socket.
- [ ] **7.2** Git-aware diff/merge view for level JSON.
- [ ] **7.3** Collaborative editing via a shared project folder with lock
      files.
- [ ] **7.4** Embedded play-test in a studio panel (decision D4 alternative).
- [ ] **7.5** Plugin API for third-party node kinds and inspector widgets.

## Documentation

Site: <https://meetarash.ir/agentic-game-engine/> (MkDocs Material, built from
`docs/` by `.github/workflows/docs.yml`). Conventions:
[docs/contributing-docs.md](docs/contributing-docs.md).

### Coverage gaps — shipped features with no guide yet

None of these appear anywhere under `docs/` today. Each needs a concept page
(or a section) and, where it has runtime behaviour, a tested recipe:

- [ ] Localization (`LocalizationManager`, RTL, plurals, ARB/CSV/JSON).
- [ ] Dialogue (`DialogueGraph`, `DialogueRunner`, `DialogueBoxScene`) and the
      visual-scripting graph compiler.
- [ ] Procedural level generation (BSP, cellular automata, WFC).
- [ ] AI building blocks: behavior trees, state machines, steering, hearing /
      sound propagation, `InvestigateBehavior`, pathfinding.
- [ ] Particles, tweening, cinematics, scene transitions, video playback.
- [ ] Settings menus, `PlayerOptions` persistence and accessibility options
      (colorblind modes, text scaling, remapping).
- [ ] Viewport / aspect-ratio / safe-area handling.
- [ ] Error reporting and analytics hooks.
- [ ] Performance: archetypes, the job system, the benchmark suite.
- [ ] Lighting deep-dive (`Light2D`, shadows, single-pass shader, day/night)
      beyond the overview in `concepts/rendering.md`.
- [ ] Release pipeline (`build-release`) walkthrough: signing for Android and
      iOS.
- [ ] A "build your first level" studio tutorial (the user guide, `docs/studio/user-guide.md`,
      is done).

### Quality of the docs themselves

- [ ] **Execute the platformer samples** — tutorial 1 and the older recipes
      are checked by hand; give them the same test treatment as the
      turn-based ones (`doc_examples_test.dart`), and fix any drift found.
- [ ] **Generate the events reference** — `docs/reference/events.md` is
      hand-written and can drift; generate it from source (like the component
      reference) or add a test that every `*Event` class is listed.
- [ ] **Doc-comment audit** — several `dart doc` warnings remain in
      `engine_core` (unresolved references); `dart doc` should be clean in CI.
- [ ] **API docs for the Flutter packages** — only `engine_core` and
      `engine_schema` are generated on the site. Add `engine_flutter`,
      `engine_platformer`, `engine_strategy` via the Flutter SDK in the docs
      workflow.
- [ ] **Versioned docs** — publish per-release versions (e.g. with `mike`)
      once tags exist; the site is single-version today.
- [ ] **Publish or retire the unpublished pages** — `docs/proposals/` and
      `docs/studio/` are excluded from the site; decide which are public.
- [ ] **Diagrams and screenshots** — add real screenshots (strategy template,
      studio) to the tutorials and getting-started.
- [ ] **Keep the docs claims honest** — the landing page says the turn-based
      samples are test-executed; extend that guarantee (and the sentence) as
      other samples gain tests.
- [ ] **README badges** — still static placeholders; point at real pub.dev
      badges once packages are published (see Release).

## Release

- [ ] Push the locally tagged `v0.1.0` (CHANGELOG says it exists only
      locally), and decide the tag / `ref` policy for generated projects.
- [ ] Publish the packages to pub.dev. That removes the self-referencing git
      dependency constraint documented in CLAUDE.md and `game_agent upgrade`'s
      `ref` matching limitation.
- [ ] Replace placeholder README badges with real ones after publishing.
- [ ] Add `engine_strategy` to any release/versioning checklist alongside the
      other packages (it is `0.1.0`, `publish_to: none`).

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
