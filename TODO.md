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

- [x] **Dialogue / branching-conversation system** — `DialogueGraph`/`DialogueNode`/`DialogueChoice` (`content/dialogue.dart`, plain-JSON round-trip like `Level`/`Cinematic`) plus a `DialogueRunner` driven on demand (not a `System`) that resolves choices through `StringTable` and emits each choice's event onto `EventBus`. `DialogueBoxScene` (`ui/dialogue_box_scene.dart`) renders it.

- [x] **AI steering primitives** — `seek`/`arrive`/`wander` (`ai/steering.dart`) — plain functions, not `Behavior`s, meant as shared math for `FollowBehavior`/`AvoidanceBehavior` to call into. `arrive` gives a decelerating approach instead of `FollowBehavior`'s hard stop/start at `stopDistance`.

- [x] **FollowBehavior.jumpAcrossGaps** — An NPC blocked by a gap it's physically capable of clearing now requests a real jump (via `PlatformerController.jumpRequested`, the same field player input sets) computed from the same arc math `JumpSystem` uses, instead of just walking up to the edge and stopping.

- [x] **AttackSystem.requireLineOfSight** — Gates melee/ranged attacks on `WorldView.hasLineOfSight`, the same convention `FollowBehavior`/`FleeBehavior` already use — an attacker behind a wall from its target no longer fires through it. Cooldown still ticks down while blocked.

- [x] **Hearing / sound propagation** — `SoundEvent` (`ai/hearing.dart`) is an `EventBus` event any system can emit; `HearingSystem` matches it against every `HearingComponent`-bearing entity's range and tile occlusion (reusing `raycastTileMap`'s traversal) and writes a heard position into that entity's `AIState.memory` blackboard. `InvestigateBehavior` consumes it to walk the NPC toward the last-heard sound.

- [x] **TileMap collision layers/groups** — `Collider.collisionGroup`/`collisionMask` and a matching per-tile-id `TileMap.collisionGroups` bitmask, checked by both `CollisionSystem` and `TileCollisionSystem` — lets a level or spawn helper put player, enemies, and projectiles in different collision groups (e.g. so enemies stop colliding with each other) without affecting who still collides with solid tiles.

- [x] **Camera shake enhancements** — `Camera.shake` grew named params (`frequency`, `decay`, `impulse` for a sharp one-time hit vs. sustained, `axis` for per-axis shake, `stack` for additive multiple shakes) on top of the original `shake(magnitude, duration)`.

- [x] **TileMap auto-tile bitmask debug overlay** — `EngineView.showAutoTileBitmask` draws each auto-tiled cell's computed neighbor bitmask with a hover tooltip, now also wired through `GameConfig.showAutoTileBitmask`/`Scene.showAutoTileBitmask` so a game can actually turn it on.

- [x] **Single-pass ambient-lighting shader** — `ambient_lighting.frag` computes the combined darkness mask for every light in one fragment shader invocation instead of the legacy `saveLayer` + per-light draw path (1 draw instead of 1+N). Opt-in via `EngineView.singlePassLighting`/`GameConfig.singlePassLighting` (default `false`); falls back to the legacy path for any light using `castsShadows`, `coneAngle`, or `useGpuShadows`.

- [x] **Particle rendering batching** — Plain (spriteless) particles now batch through one `Canvas.drawAtlas` call per `zIndex` via a new tiny cached `ParticleDotTexture`, instead of one `drawCircle`/`Paint` pair per particle. Falls back per-particle to the original `drawCircle` path for any frame before the texture's one-time async generation resolves or for a particle that carries its own registered `Sprite`.

- [x] **AnimationClip.sequence memoization** — Memoized by its full argument set — a call site that rebuilds the same sequence repeatedly (e.g. from `Scene.populate`, which reruns on every scene reload/room transition) gets the same cached instance back instead of re-running `List.generate`/reallocating a fresh clip every time.

- [x] **Gravity.fallMultiplier** — An extra gravity multiplier `GravitySystem` applies only while an entity is already falling (`Velocity.y > 0`), independent of `Gravity.scale` (which speeds up rise and fall equally, changing jump height/reach too). The standard "floaty rise, snappy fall" platformer feel — `1` (default) is no asymmetry, identical to every jump before this field existed.

- [x] **ParallaxLayer.fitHeight** — Stretches a background region to exactly the viewport's height instead of native size (optionally tiled).

- [x] **Documentation site** — Added a top-level `docs/` tutorial/concept layer (`docs/README.md`, `docs/getting-started.md`, `docs/concepts/{ecs,content-as-data,agent-api,rendering,platformer}.md`, `docs/tutorials/01-hello-world.md`, `docs/examples/{README,spawn-enemy-with-patrol-ai,health-bar,save-load,custom-behavior}.md`), written for both human developers and AI coding agents, with every code sample checked against current signatures under `packages/*/lib/src/`.

- [x] **Flutter Web CanvasKit text rendering fix** — Bundled Roboto Regular as `EngineDefault` font family (`engine_flutter/assets/fonts/EngineDefault-Regular.ttf`, declared in `engine_flutter/pubspec.yaml`) so `Text` has a default typeface it owns on every platform, fixing the "dialogue box renders, text never appears" bug on web where CanvasKit has no typeface until a custom font is bundled or its default-font fetch succeeds.

- [x] **Colorblind shader Impeller compatibility** — Changed `uniform int uColorblindType` to `float` in `shaders/colorblind.frag` (rounded on read) to fix "Non-floating-type struct member ... is not supported" error under Impeller that broke `flutter test` asset bundling for every `engine_flutter`-dependent package.

- [x] **Scene transition effects** — Fade and iris transitions between scenes. Configurable duration/easing. Implemented in `engine_flutter/lib/src/logic/scene_transition.dart` with `SceneTransitionType`, `SceneTransitionConfig`, `SceneTransition`, `SceneTransitionSystem`, plus `SceneController.loadSceneWithTransition` / `GameRunner._loadSceneWithTransition` driving it as two phases (cover the outgoing scene, swap `World`s, reveal the incoming one) across the existing `World`-per-scene swap. Uses existing `ScreenTint` (fade) and `ClipShape` (iris) components for rendering — no multi-scene rendering needed, since only one `World` is ever live at a time. Slide/crossfade/pixel-dissolve still require true multi-scene rendering (both scenes' `World`s drawn simultaneously) and remain future work.

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
- [x] **Accessibility (colorblind-safe palettes, text scaling, full input remapping)** — Implemented in `engine_core/lib/src/content/player_options.dart` + `engine_flutter/lib/src/rendering/text.dart` + `engine_flutter/lib/src/ui/settings_menu.dart` + `engine_flutter/shaders/colorblind.frag`. Supports colorblind modes (protanopia/deuteranopia/tritanopia), high contrast, reduce motion, text scaling, full keyboard/touch remapping via SettingsKeyBindingSpec and AccessibilitySettingsMenu.
- [x] **Crash/error reporting hook** — Pluggable error-reporting sink exists (e.g. wiring `FlutterError.onError`/a zone guard to Sentry/Crashlytics) to diagnose field crashes post-launch. Implemented in `engine_flutter/lib/src/logic/error_reporting.dart` with `ErrorReporter`, `ConsoleErrorReporter`, `NoOpErrorReporter`, `ErrorReportingManager`, and `runWithErrorReporting` helpers. Backends in `engine_flutter/lib/src/logic/error_reporting_backends.dart`: `SentryErrorReporter`, `FirebaseCrashlyticsReporter`, `GooglePlayReporter`, `CustomHttpReporter`, `MultiErrorReporter`.
- [x] **Achievements / analytics event hooks** — Generic "fire named event with payload" abstraction implemented in `engine_core/lib/src/content/analytics.dart` + `engine_flutter/lib/src/logic/analytics_flutter.dart`. Supports multiple providers (Firebase, Game Center, custom), batching, offline queue, with convenience methods for achievements, purchases, level events, screen views.
- [x] **Release build/packaging pipeline** — Implemented `engine_cli` command `build-release` for signed Android AAB (with keystore, split-per-abi) and iOS IPA (team ID, provisioning profile, codesign identity). Reads version from pubspec.yaml, supports dry-run and verbose modes.
- [x] **Cutscene video playback** — `CinematicSystem` only sequences steps over engine primitives (camera/tween/etc.), not playback of a pre-rendered video file, which many shipped games use for opening logos or non-interactive intro cutscenes. Implemented in `engine_flutter/lib/src/rendering/video_player.dart` with `VideoPlayer`, `PlayVideoStep`, `VideoScene`, and `VideoCinematicExtension`.
- [ ] **Local split-screen multiplayer** — gamepad TODO above only covers per-player input bindings; there's no viewport-splitting or multi-camera/multi-`WorldView` simulation support to actually render and drive split-screen play. Viewport split in `engine_flutter`, multi-context support in `engine_core`.

- [x] **Credits/attribution scene** — Scrolling credits/attribution scene implemented in `engine_flutter/lib/src/ui/credits_scene.dart`. Supports styled entries, auto-scroll, tap-to-skip, and optional skip hint.

## Engine Polish / Quality of Life

- [x] **Save slot thumbnails** — Screenshot capture when saving, display in SaveSlotMenuScene. `SceneController.captureScreenshot` (`logic/game.dart`/`logic/scene.dart`) snapshots the base scene's `EngineView` via a `RepaintBoundary` as PNG bytes, for `SaveGame.save`'s existing `thumbnail` parameter. `SaveSlotMenuScene` (`ui/save_slot_menu_scene.dart`) decodes each slot's saved thumbnail and shows it next to that slot's button via a new `ButtonMenuScene.onButtonSpawned` hook.
- [ ] **Input action aliases** — Friendly names for actions (e.g., "Jump" vs "action_0") shown in remap menus and debug overlay.
- [ ] **Debug overlay improvements** — FPS graph, memory graph, entity inspector with component values.
- [x] **Localization system** — Language switching, RTL support, pluralization, date/number formatting. JSON/CSV/ARB resource files. Implemented in `engine_core/lib/src/content/localization.dart` + `engine_flutter/lib/src/logic/localization_flutter.dart` with `LocalizationManager`, `LocaleInfo`, `LocalizedString`, `LocalizationFlutter`, `RTLWidget`, and extension methods.
- [ ] **Asset hot-reload** — Watch assets folder, reload textures/atlases/levels without restart. Invalidate caches on file change.
- [x] **Scene transition effects (fade/iris)** — see "New engine features" above for the full writeup; duplicated here before, now tracked in one place. Slide/crossfade/pixel-dissolve remain open, see the item directly below.
- [ ] **Scene transition effects (slide/crossfade/pixel-dissolve)** — needs true multi-scene rendering (both the outgoing and incoming `World`s drawn in the same frame), unlike the fade/iris transitions already shipped — see "New engine features" above.
- [ ] **Network multiplayer foundation** — ECS state serialization, rollback networking, lag compensation, state sync.
- [ ] **Visual scripting / node editor** — Extend BT/FSM visual editor to general logic (dialogue, cutscenes, AI, quests).
- [ ] **Level editor integration** — TileMap editor, entity placement, autotile painting, prefab brushes. Export to level JSON.
- [ ] **Documentation site** — Auto-generated from doc comments, versioned, searchable. Host on GitHub Pages.
- [ ] **Example game** — Complete small game showing all features (platformer, RPG, puzzle). Playable in browser.
- [ ] **Performance profiling tools** — Frame time breakdown, GPU/CPU timers, allocation tracker, shader compile time.

(End of file)