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

- [ ] **Platformer-aware NavMesh / A* pathfinding** — Current pathfinding is tile-based (basic A* in `pathfinding.dart`, `PathFollowBehavior` exists); need a platformer-aware pathfinder that handles jumps, one-way platforms, ladders, and moving platforms. Output: sequence of `PathPoint` with `jumpRequired` flags consumable by a `PathFollowBehavior`.

- [ ] **Behavior Tree / State Machine** — Replace ad-hoc `Behavior` implementations with a serializable BT/FSM. Nodes: Sequence, Selector, Parallel, Decorator (Inverter, Repeater), Leaf (custom `Behavior`). Visual editor export → JSON → runtime interpreter.

- [ ] **Dialogue system enhancements** — Variables/conditions in dialogue (`{if has_sword}...`), branching by inventory/flags, localized audio per line, portrait sprites, typewriter effect, skip/replay.

- [ ] **Particle system upgrades** — Emitters attached to entities (follow Position), attractors/repellers (gravity wells, wind), GPU instanced particles via single draw call, emission shapes (circle, rect, edge), collision with TileMap.

- [ ] **Save/load system enhancements** — Version migration (`GameState.migrationVersion`), screenshot thumbnails, checksum validation, cloud sync hook. (Base `SaveGame`, `SaveSlotMenuScene` exist.)

- [ ] **Cutscene / Timeline system enhancements** — Visual editor, more step types (`MoveCamera`, `SpawnEntity`, `PlaySound`, `SetFlag`). Base `CinematicSystem` with `WaitStep`, `CallbackStep`, `TweenStep`, skip support exists.

- [ ] **Input remapping / Gamepad improvements** — Dead zones, vibration (haptics), multiple local players (split-screen), virtual gamepad layout editor, Steam Input / SDL gamepad DB integration. (Base `GamepadController`, bindings storage, haptic feedback exist.)

- [ ] **2D Normal mapping / Sprite lighting** — Normal map atlas per sprite, per-pixel lighting with depth (parallax occlusion optional). `Sprite.normalAtlasId` + `Light2D` reads normal for Lambertian shading.

- [ ] **Audio: Spatial audio / Occlusion** — Distance attenuation (inverse square / linear), low-pass filter behind walls (reuse `hasLineOfSight`), reverb zones, Doppler for moving sources.

- [ ] **ECS query caching / Archetypes** — Hot loops (`MovementSystem`, `CollisionSystem`) iterate archetype tables instead of sparse sets. Cache invalidation on component add/remove.

- [ ] **Job system / Multithreaded systems** — Offload `TileCollisionSystem` broadphase, `Pathfinding`, `ParticleSystem` to background isolates. Main thread only commits results.

- [ ] **Visual Behavior Tree editor (web)** — Browser-based node graph editor exporting BT JSON, loads into engine at runtime. Drag-drop nodes, live preview.

- [ ] **Procedural level generation** — Room/corridor (BSP), cellular automata caves, wave-function collapse for tile patterns. Seeded, deterministic, JSON output.

## For zahaak

Engine gameplay features the `zahaak` game design (local-only,
gitignored `/zahaak/`, GDD at `zahaak/docs/GDD.md`) needs but the
engine doesn't have yet — surfaced by
`zahaak/docs/engine-gap-analysis.md` while writing the GDD, before any
implementation started. Not scoped/sequenced yet; revisit once the
GDD's combat/dialogue scope is locked down.

- [ ] **Multi-hit melee combo chains** — `Weapon` currently fires one
      attack per cooldown; no input-buffered chain of N attacks
      (light-light-light) with per-hit timing windows and combo reset
      on miss/delay.
- [ ] **Guard/block + breakable stability meter** — neither `Health`
      nor `Weapon` models blocking an incoming hit or a stability/
      poise value that depletes on blocked hits and breaks guard when
      exhausted.
- [ ] **Parry / precise-deflect** — a short input-timing window (not
      `DashSystem`, not `Health`'s invincibility window) that, on a hit
      landing inside it, opens the attacker up instead of damaging the
      defender.
- [ ] **Enemy combat state machine with explicit telegraph** — `AISystem`
      only has patrol/follow/path-follow/avoidance `Behavior`s; no
      `Idle→Patrol→Alert→Approach→Telegraph→Attack→Recovery→Reposition`
      state machine (plus `Stagger`/`Guard`/`Retreat`) for a melee
      enemy that visibly winds up before attacking.
- [ ] **Multi-phase boss encounters** — no component/system for a boss
      with distinct attack-pattern phases and phase-transition
      conditions (health thresholds, scripted triggers).
- [ ] **Dialogue system with speaker + trigger conditions** — only
      `StringTable` (key → localized string, `{param}` substitution)
      exists; no turn-based dialogue flow, speaker portraits, or
      condition-gated lines (`DialogueBoxScene` in engine_flutter is a
      display widget, not a dialogue-authoring/branching system — check
      whether "Dialogue system enhancements" above already covers this
      before starting new work).

## Shipping a full game

Gaps that don't block a tech demo/sample (`test_game` already exercises
most engine features) but would block actually shipping a complete,
real game with this engine as-is — surfaced by auditing what a small
team releasing a real 2D game needs that nothing above already covers.

- [ ] **Settings-menu widgets (checkbox, slider, dropdown, scrollable list)** — `engine_flutter/lib/src/ui` only has `Button`/`ButtonMenuScene`/`RemapMenuScene`/`SaveSlotMenuScene`/`DialogueBoxScene`; there's no toggle/slider/dropdown/scroll-list widget, so a real options screen (volume sliders, graphics toggles, a scrollable keybind list) means every game hand-rolling hit-testing widgets from scratch. `engine_flutter`.
- [ ] **Aspect-ratio / safe-area handling for rendering and UI** — `EngineView`/`Camera` have no letterbox/pillarbox logic, and safe-area insets are only handled inside `on_screen_controls.dart` for touch buttons, not general HUD/menu layout — a notched or unusual-aspect device will clip or misplace UI. `engine_flutter`.
- [ ] **Player options persistence (separate from save-game slots)** — `GameConfig` is a static file-loaded config, and `SaveGame`/`SaveSlotMenuScene` are gameplay saves; there's no dedicated "player options" store (volume, control scheme, accessibility flags) a settings menu reads/writes independent of a save slot. `engine_flutter`.
- [ ] **Accessibility (colorblind-safe palettes, text scaling, full input remapping)** — no colorblind/text-scale support anywhere; `RemapMenuScene` only covers gamepad rebinding (see its own TODO history), not keyboard/touch remapping or the text-scale/high-contrast modes app stores' accessibility requirements expect. Data flags in `engine_core`, rendering/scaling in `engine_flutter`.
- [ ] **Crash/error reporting hook** — no pluggable error-reporting sink exists (e.g. wiring `FlutterError.onError`/a zone guard to Sentry/Crashlytics) to diagnose field crashes post-launch — the GPU-shadow bug above was only ever caught by a manual release-APK install, not any reporting pipeline. `engine_flutter`.
- [ ] **Achievements / analytics event hooks** — no generic "fire named event with payload" abstraction a game could wire to Game Center / Play Games / any analytics SDK, which most shipping mobile games need for both engagement and store requirements. Event data in `engine_core`, platform sink in `engine_flutter`.
- [ ] **Release build/packaging pipeline** — the repo's CI only runs each package's test suite; there's no `engine_cli` command or reference workflow producing a signed release Android AAB/iOS build, so catching a release-only bug (like the GPU-shadow one) still means a manual local build every time. `engine_cli`.
- [ ] **Cutscene video playback** — `CinematicSystem` only sequences steps over engine primitives (camera/tween/etc.), not playback of a pre-rendered video file, which many shipped games use for opening logos or non-interactive intro cutscenes. `engine_flutter`.
- [ ] **Local split-screen multiplayer** — gamepad TODO above only covers per-player input bindings; there's no viewport-splitting or multi-camera/multi-`WorldView` simulation support to actually render and drive split-screen play. Viewport split in `engine_flutter`, multi-context support in `engine_core`.
- [ ] **Credits/attribution scene** — no scrolling-credits primitive exists among the current `Scene` types; shipping to app stores (and satisfying third-party asset licenses) generally needs one, and there's currently no auto-scrolling long-form-text building block to build it from. `engine_flutter`.
