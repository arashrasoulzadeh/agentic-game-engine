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
      service with NAT traversal, authentication and `wss://` guidance, and a Flutter widget
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

- [ ] **Real-time strategy, remaining** — gathering and building are done (see the concept
      guide). Tech trees (prerequisites by building or by name) are also done. Missing:
      builder units that must be present to construct, and per-unit collision radii larger than one cell.

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

- [ ] **6.2 / 6.3 (remaining)** The preview now has a profiler panel (`WorldProfiler`: step cost,
      entity count, step-time sparkline, slowest systems). Not done: `FrameStats` /
      `FrameTimingMonitor` render metrics, and profiling a *separate* play-test process (the
      external `PlayTest` is not wired into the studio UI yet, so there is no channel to build).
- [ ] **Run game, remaining** — the device is fixed to `macos` and the game process is not
      stopped when the studio closes or the button is pressed again; add a device choice and
      process management.
- [ ] **6.6** (remaining) Move the rest of the studio's strings to `StudioStrings`
      (the mechanism and the project window are done; level, graph, code and
      inspector screens still hold English literals) and ship a first non-English
      catalog.

### Stretch (not scheduled)

- [ ] **7.1** Live reload of levels into a running game over a local socket.
- [ ] **7.2 (remaining)** A visual diff/merge view in the studio (the engine-side `diffLevels` /
      `mergeLevels`, `studio diff` / `studio merge` and a git merge-driver recipe are done).
- [ ] **7.3 (remaining)** Real-time presence and live refresh of another person's saved edits;
      advisory per-level locks are done (`FileLock`, the studio banner, `studio lock`/`unlock`).
- [ ] **7.4** Embedded play-test in a studio panel (decision D4 alternative).
- [ ] **7.5** Plugin API for third-party node kinds and inspector widgets.

## Documentation

Site: <https://meetarash.ir/agentic-game-engine/> (MkDocs Material, built from
`docs/` by `.github/workflows/docs.yml`). Conventions:
[docs/contributing-docs.md](docs/contributing-docs.md).

### Coverage gaps — shipped features with no guide yet

None of these appear anywhere under `docs/` today. Each needs a concept page
(or a section) and, where it has runtime behaviour, a tested recipe:

- [ ] `InvestigateBehavior.timeout` is accepted but ignored (no timestamp in `lastHeardSound`).
- [ ] Cinematics, scene transitions, video playback (tweens and particles are done:
      `docs/concepts/effects.md`).
- [ ] **Colorblind simulation is an unimplemented placeholder** (`EngineView._drawColorblind`,
      `shaders/colorblind.frag` exists); and nothing in the engine applies `PlayerOptions` such as
      `reduceMotion` or `screenShakeIntensity` - decide which should be engine behaviour.
- [ ] **Viewport / aspect-ratio / safe-area handling is not usable yet** (`rendering/viewport.dart`,
      opt-in via `EngineView.viewportConfig`; no tests, nothing wires it from `GameConfig`, and
      `test_game` does not use it). `ViewportManager.computeLayout` computes `scale` as
      `height / (ratio * height)` = `1 / ratio` whatever the screen, then multiplies the content size
      by it, so even a screen that matches the target ratio gets a shrunken, letterboxed rect;
      `ViewportFit.cover` runs the same arithmetic as `contain` (it does not crop/fill); and the
      config has no reference resolution to define what `scale` is relative to. Needs a design
      (what is one world unit at zoom 1?), then tests, then a guide. Do not document it until then.
- [ ] Release pipeline (`build-release`) walkthrough: signing for Android and
      iOS.
- [ ] A "build your first level" studio tutorial (the user guide, `docs/studio/user-guide.md`,
      is done).

### Quality of the docs themselves

- [ ] **Versioned docs** — publish per-release versions (e.g. with `mike`)
      once tags exist; the site is single-version today.
- [ ] **Publish or retire the unpublished pages** — `docs/proposals/` and
      `docs/studio/` are excluded from the site; decide which are public.
- [ ] **Diagrams and screenshots** — add real screenshots (strategy template,
      studio) to the tutorials and getting-started.
- [ ] **Extend the executed-samples guarantee** to the multiplayer tutorial and the older concept pages
      (ECS, architecture, networking, rendering, real-time strategy); the landing page lists what is
      covered and what is not.
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
