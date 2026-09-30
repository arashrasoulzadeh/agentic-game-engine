# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered.

Everything completed has been cleared from this file — see
[CHANGELOG.md](CHANGELOG.md) for what shipped and git history for the
full why behind each change. [TODO_RENDER.md](TODO_RENDER.md) tracks
parked rendering-architecture discussion points not yet scoped into
actionable items here.

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


## New engine features

- [x] **ECS query caching / Archetypes** — Hot loops (`MovementSystem`, `CollisionSystem`) iterate archetype tables instead of sparse sets. Cache invalidation on component add/remove. Implemented in `engine_core/lib/src/ecs/archetype.dart` with `Archetype`, `ArchetypeManager`, `ArchetypeEntity`.

- [x] **Job system / Multithreaded systems** — Offload `TileCollisionSystem` broadphase, `Pathfinding`, `ParticleSystem` to background isolates. Main thread only commits results. Implemented in `engine_core/lib/src/ecs/job_system.dart` with `JobSystem`, `Job`, `CollisionBroadphaseJob`, `PathfindingJob`.

- [x] **Procedural level generation** — Room/corridor (BSP), cellular automata caves, wave-function collapse for tile patterns. Seeded, deterministic, JSON output. Implemented in `engine_core/lib/src/physics/procedural_generation.dart` with `BSPGenerator`, `CellularAutomataGenerator`, `WFCGenerator`, `ProceduralLevelGenerator`.

## For zahaak

Engine gameplay features the `zahaak` game design (local-only,
gitignored `/zahaak/`, GDD at `zahaak/docs/GDD.md`) needs but the
engine doesn't have yet — surfaced by
`zahaak/docs/engine-gap-analysis.md` while writing the GDD, before any
implementation started. Not scoped/sequenced yet; revisit once the
GDD's combat/dialogue scope is locked down.

## Shipping a full game

Gaps that don't block a tech demo/sample (`test_game` already exercises
most engine features) but would block actually shipping a complete,
real game with this engine as-is — surfaced by auditing what a small
team releasing a real 2D game needs that nothing above already covers.

- [x] **Settings-menu widgets (checkbox, slider, dropdown, scrollable list)** — Implemented in `engine_flutter/lib/src/ui/settings_menu.dart` with `SettingsToggleSpec`, `SettingsSliderSpec`, `SettingsDropdownSpec`, `SettingsListSpec`, `SettingsSectionSpec`, and `SettingsMenuScene` base class extending `ButtonMenuScene`. Binds to `PlayerOptionsManager` for persistence.
- [x] **Aspect-ratio / safe-area handling for rendering and UI** — `EngineView`/`Camera` have no letterbox/pillarbox logic, and safe-area insets are only handled inside `on_screen_controls.dart` for touch buttons, not general HUD/menu layout — a notched or unusual-aspect device will clip or misplace UI. Implemented in `engine_flutter/lib/src/rendering/viewport.dart` with `ViewportConfig`, `ViewportManager`, `ViewportLayout`. Integrated with `Camera` and `EngineView`.
- [x] **Player options persistence (separate from save-game slots)** — `GameConfig` is a static file-loaded config, and `SaveGame`/`SaveSlotMenuScene` are gameplay saves; there's no dedicated "player options" store (volume, control scheme, accessibility flags) a settings menu reads/writes independent of a save slot. Implemented in `engine_core/lib/src/content/player_options.dart` + `engine_flutter/lib/src/logic/player_options_flutter.dart` with `PlayerOptions`, `PlayerOptionsManager`, `shared_preferences` storage.
- [ ] **Accessibility (colorblind-safe palettes, text scaling, full input remapping)** — Implemented in `engine_core/lib/src/content/player_options.dart` + `engine_flutter/lib/src/rendering/text.dart` + `engine_flutter/lib/src/ui/settings_menu.dart` + `engine_flutter/shaders/colorblind.frag`. Supports colorblind modes (protanopia/deuteranopia/tritanopia), high contrast, reduce motion, text scaling, full keyboard/touch remapping via SettingsKeyBindingSpec and AccessibilitySettingsMenu.
- [x] **Crash/error reporting hook** — Pluggable error-reporting sink exists (e.g. wiring `FlutterError.onError`/a zone guard to Sentry/Crashlytics) to diagnose field crashes post-launch. Implemented in `engine_flutter/lib/src/logic/error_reporting.dart` with `ErrorReporter`, `ConsoleErrorReporter`, `NoOpErrorReporter`, `ErrorReportingManager`, and `runWithErrorReporting` helpers. Backends in `engine_flutter/lib/src/logic/error_reporting_backends.dart`: `SentryErrorReporter`, `FirebaseCrashlyticsReporter`, `GooglePlayReporter`, `CustomHttpReporter`, `MultiErrorReporter`.
- [x] **Achievements / analytics event hooks** — Generic "fire named event with payload" abstraction implemented in `engine_core/lib/src/content/analytics.dart` + `engine_flutter/lib/src/logic/analytics_flutter.dart`. Supports multiple providers (Firebase, Game Center, custom), batching, offline queue, with convenience methods for achievements, purchases, level events, screen views.
- [x] **Release build/packaging pipeline** — Implemented `engine_cli` command `build-release` for signed Android AAB (with keystore, split-per-abi) and iOS IPA (team ID, provisioning profile, codesign identity). Reads version from pubspec.yaml, supports dry-run and verbose modes.
- [ ] **Cutscene video playback** — `CinematicSystem` only sequences steps over engine primitives (camera/tween/etc.), not playback of a pre-rendered video file, which many shipped games use for opening logos or non-interactive intro cutscenes. Implemented in `engine_flutter/lib/src/rendering/video_player.dart` with `VideoPlayer`, `PlayVideoStep`, `VideoScene`, and `VideoCinematicExtension`.
- [ ] **Local split-screen multiplayer** — gamepad TODO above only covers per-player input bindings; there's no viewport-splitting or multi-camera/multi-`WorldView` simulation support to actually render and drive split-screen play. Viewport split in `engine_flutter`, multi-context support in `engine_core`.

- [x] **Credits/attribution scene** — Scrolling credits/attribution scene implemented in `engine_flutter/lib/src/ui/credits_scene.dart`. Supports styled entries, auto-scroll, tap-to-skip, and optional skip hint.
