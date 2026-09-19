# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered.

Everything completed has been cleared from this file — see
[CHANGELOG.md](CHANGELOG.md) for what shipped and git history for the
full why behind each change. [TODO_RENDER.md](TODO_RENDER.md) tracks
parked rendering-architecture discussion points not yet scoped into
actionable items here.

## Performance

- [x] Avoid `saveLayer`+`dstOut` for the ambient-lighting overlay
      entirely — implemented single-pass shader (`ambient_lighting.frag`)
      that computes combined darkness mask for all lights in one fragment
      shader invocation. One full-screen quad draw replaces 1+N draws
      inside a saveLayer. Enabled via `EngineView.singlePassLighting` /
      `GameConfig.singlePassLighting` (default `false` for compat).
      Falls back to legacy path for lights with `castsShadows`,
      `coneAngle`, or `useGpuShadows`.
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

- [ ] **Dialogue / branching-conversation system.**
      New file `packages/engine_core/lib/src/content/dialogue.dart`:
      - `DialogueChoice { String textKey; String? conditionEventFlag;
        Object onSelectEvent; String? nextNodeId }` — `conditionEventFlag`
        is a simple world-state key checked via `WorldView` (reuse
        whatever flag/inventory lookup pattern `checkpoint_helpers.dart`
        already established; don't invent a second one).
      - `DialogueNode { String id; String textKey; List<DialogueChoice>
        choices }`, `DialogueGraph { Map<String, DialogueNode> nodes;
        String startNodeId }`, both with `toJson`/`fromJson` following
        the exact same plain-JSON convention as `Level`/`Cinematic`
        (see `content/level.dart`, `content/cinematic.dart` for the
        shape to match) — this is content data, must round-trip through
        `World.toJson()`/`applyPatch()` like everything else.
      - `DialogueRunner` (not a `System` — driven on demand, like
        `ReplayRecorder`, not every tick): `currentNode`, `advance
        (int choiceIndex)` which emits the choice's `onSelectEvent` onto
        `world.events` (`EventBus.emit`, see `event_bus.dart`) and moves
        to `nextNodeId`, resolving `textKey`s through `StringTable`
        (`content/string_table.dart`) for the actual display string.
      - Register `DialogueGraph` in `registerCoreComponents`
        (`engine_core.dart`) if a node's graph is ever attached to an
        NPC entity as a component (needed for it to survive
        `World.toJson()`/save-load) — check `component_registry.dart`'s
        `register<T>()` signature before writing this.
      - New file `packages/engine_flutter/lib/src/ui/dialogue_box_scene.dart`
        modeled directly on `ui/save_slot_menu_scene.dart` (same
        Scene-subclass shape, same pattern for wiring button/text
        widgets) — renders `DialogueRunner.currentNode`'s text and
        choices, calls `.advance()` on selection. Keep all graph logic
        in `DialogueRunner`; this file is render/input glue only.
      - Tests: `packages/engine_core/test/dialogue_test.dart` —
        selecting a choice emits the right event and moves to the right
        node; a choice gated by a false `conditionEventFlag` is excluded
        from the presented options; `toJson`/`fromJson` round-trips a
        graph with 2+ nodes. No rendering test needed beyond a
        does-not-crash smoke test for `DialogueBoxScene`, consistent
        with this repo's rendering-heavy-widget-test exception.
      Reference: `content/level.dart`, `content/cinematic.dart`,
      `content/string_table.dart`, `ecs/event_bus.dart`,
      `logic/checkpoint_helpers.dart`, `ui/save_slot_menu_scene.dart`,
      `component_registry.dart`; docs `docs/concepts/content-as-data.md`
      (the JSON-content contract this must follow) and
      `docs/concepts/ecs.md` (event/component registration).

- [ ] **Steering-behavior primitives (`seek`/`arrive`/`wander`).**
      New file `packages/engine_core/lib/src/ai/steering.dart` (sibling
      to `ai/flee_behavior.dart`), plain functions, not `Behavior`
      classes — `flee_behavior.dart`/`avoidance_behavior.dart` (the
      latter in `engine_platformer`) are the *consumers* that would call
      these, mirroring how `collision_math.dart` holds shared math that
      `PlatformerSystem`/`TileCollisionSystem` both call rather than
      being a `System` itself:
      - `Velocity seek(Position from, Position to, double maxSpeed)` —
        straight-line velocity toward `to` at `maxSpeed`.
      - `Velocity arrive(Position from, Position to, double maxSpeed,
        double slowRadius)` — like `seek` but linearly scales speed down
        inside `slowRadius` so a chaser settles next to its target
        instead of overshooting/oscillating (this is the concrete gap
        `FollowBehavior`'s `stopDistance` papers over with a hard
        stop/start rather than an actual decelerate).
      - `Velocity wander(Velocity current, double jitter, double
        maxSpeed, Random rng)` — small random heading perturbation each
        call, clamped to `maxSpeed`; take `Random` as a parameter (don't
        instantiate one internally) so a caller can pass
        `DeterministicRandom` (`ecs/deterministic_random.dart`) and keep
        replay determinism, per this repo's existing convention.
      - Tests in `packages/engine_core/test/steering_test.dart`: `seek`
        points directly at target at `maxSpeed`; `arrive` speed
        decreases monotonically as distance shrinks inside `slowRadius`
        and is exactly `maxSpeed` outside it; `wander` given a seeded
        `DeterministicRandom` produces the same sequence twice (the
        actual behavior to assert, not just "doesn't crash").
      Reference: `ai/flee_behavior.dart`,
      `packages/engine_platformer/lib/src/ai/avoidance_behavior.dart`
      (decorator pattern this could plug into),
      `physics/collision_math.dart` (shared-math precedent to follow),
      `ecs/deterministic_random.dart`; doc `docs/concepts/ecs.md`.

- [ ] **NPC jump-to-reach-player.**
      Add an opt-in `jumpAcrossGaps` flag to
      `packages/engine_platformer/lib/src/ai/follow_behavior.dart`'s
      `FollowBehavior` (same "off by default, existing behavior
      unchanged" convention as `requireLineOfSight`). When chasing
      horizontally and the entity is `grounded == false`-eligible-to-jump
      but blocked (reuse whatever "is there ground ahead within reach"
      check `TileCollisionSystem`/`PlatformerSystem` already expose —
      check `collision_math.dart` first for an existing helper before
      writing a new raycast-down-ahead check), compute reachability from
      the *same* physics `JumpSystem` uses (`PlatformerController`'s
      `jumpVelocity`/gravity — do not hand-roll separate projectile-arc
      math; import and call into the existing constants/fields
      `platformer_controller.dart` already defines) to decide whether a
      jump can actually clear the gap before committing, then set
      `PlatformerController.jumpRequested = true` (the same field
      `PlatformerInputSystem` sets from player input — read
      `platformer_input_system.dart` for the exact field name/pattern to
      match) instead of returning a velocity action.
      Ordering: this behavior's `decide()` runs as part of the `AiSystem`
      pass; confirm in `installPlatformerSystems` (check
      `packages/engine_platformer/lib/src/*.dart` for where systems are
      registered) that AI runs *before* `JumpSystem` in the tick order —
      `JumpSystem`'s own doc comment warns grounding must be resolved
      before jump consumption is checked, so this new AI-requested jump
      must be requested before that same `JumpSystem` tick check, not
      after.
      Test in `packages/engine_platformer/test/follow_behavior_test.dart`
      (or wherever `FollowBehavior`'s existing tests live — check
      `behaviors_test.dart`): an NPC on one tile-platform with the
      player visible across a gap within jump range requests a jump and
      clears it over N ticks; the same gap made wider than the NPC's
      jump can clear leaves it stopped at the edge instead (regression
      guard against jumping into open air).
      Reference: `physics/jump_system.dart` (arc math + its own
      ordering-bug doc comment — read this first),
      `physics/platformer_controller.dart`,
      `physics/tile_collision_system.dart`, `physics/collision_math.dart`,
      `physics/platformer_input_system.dart` (how player input sets
      `jumpRequested`, to mirror for AI-set input),
      `ai/follow_behavior.dart`; doc `docs/concepts/platformer.md`.

- [ ] **Attack/follow gated on line-of-sight, not just range.**
      Smallest of the five — `WorldView.hasLineOfSight` and the
      `requireLineOfSight` convention already exist
      (`ecs/world_view.dart:124`, used by `FollowBehavior`/
      `FleeBehavior`), just not consulted by combat. Add
      `bool requireLineOfSight = false` to
      `packages/engine_platformer/lib/src/physics/attack_system.dart`'s
      `AttackSystem` constructor; in `update()`, before firing an attack
      for an entity with a `Position` and a target position available
      (melee/ranged both already resolve a facing/target — read the
      existing fire logic first), skip firing (but do NOT reset
      `Weapon.cooldownRemaining` — cooldown should still tick down;
      match how a range check, if any exists there, currently handles
      this) when `!worldView.hasLineOfSight(attackerPos.x, attackerPos.y,
      targetPos.x, targetPos.y)`. `AttackSystem` currently takes `World`
      directly in `update(World world, double dt)`, not a `WorldView` —
      check whether it already constructs one internally or needs
      `WorldView(world)` added locally for this check.
      Test in `packages/engine_platformer/test/attack_system_test.dart`:
      an attacker with `requireLineOfSight: true` and a solid tile
      between it and an in-range target does not fire (no projectile/
      damage spawned that tick); the same setup with a clear line fires
      normally; `requireLineOfSight: false` (default) is unaffected by
      an intervening wall, preserving current behavior exactly.
      Reference: `ecs/world_view.dart` (`hasLineOfSight`, line 124),
      `physics/raycast.dart`, `ai/follow_behavior.dart`,
      `ai/flee_behavior.dart` (both existing `requireLineOfSight`
      consumers to match the convention against),
      `physics/attack_system.dart`, `logic/weapon.dart`; doc
      `docs/concepts/agent-api.md`.

- [ ] **Hearing / sound-propagation system.**
      New files in `packages/engine_core/lib/src/ai/`:
      - `hearing.dart`: `SoundEvent { double x; double y; double
        loudness; }` (an `EventBus` event type, emitted via
        `world.events.emit(...)` the same way `CollisionEvent` already
        is — check `event_helpers.dart`/wherever `CollisionEvent` is
        emitted for the exact call site pattern to match) and a
        `HearingComponent { double range; }` registered in
        `registerCoreComponents` (`toJson`/`fromJson`, following
        `AIState`'s registration as the template —
        `engine_core.dart:94-98`).
      - `hearing_system.dart`: `HearingSystem implements System` —
        subscribes once (`world.events.on<SoundEvent>(...)`, see
        `EventBus.on` in `ecs/event_bus.dart`) to compute, per entity
        with `HearingComponent` + `Position`, whether
        `distance(entity, sound) <= min(hearing.range, sound.loudness)`
        AND the sound isn't fully tile-occluded — reuse
        `raycastTileMap`/`WorldView.hasLineOfSight`'s underlying grid
        traversal for the occlusion check (attenuate rather than fully
        block: a `hasLineOfSight`-style hard yes/no is fine for a first
        cut per this repo's incremental-feature convention; note
        graduated attenuation as a follow-up, don't build it
        speculatively now). On a heard sound within range and unoccluded,
        write the heard position into the target entity's existing
        `AIState.memory` blackboard (`ai_state.dart` — a free-form
        `Map<String, dynamic>` already designed for exactly this kind of
        cross-tick behavior state, e.g. `memory['lastHeardSound'] =
        {'x': ..., 'y': ...}`) rather than adding a new typed `AIState`
        field or a second parallel state channel.
      - `packages/engine_platformer/lib/src/ai/investigate_behavior.dart`:
        `InvestigateBehavior implements Behavior` consuming that
        `AIState` field — moves toward the last-heard position at a
        configurable speed, clears/gives up after reaching it or a
        timeout. Mirrors `FollowBehavior`'s shape closely enough to
        copy its structure as a starting point.
      - Tests: `packages/engine_core/test/hearing_system_test.dart` — a
        `SoundEvent` within an entity's `HearingComponent.range` and
        with clear line to it updates that entity's `AIState`; the same
        sound behind a fully-occluding wall thick enough to block
        `raycastTileMap` (mirror `raycast_test.dart`'s own tunnel-
        proofing test setup) does not; a sound outside `range` (even
        unoccluded) does not. Separate
        `engine_platformer/test/investigate_behavior_test.dart` for the
        behavior consuming it.
      Reference: `ecs/event_bus.dart`, `ecs/event_helpers.dart`,
      `ai/ai_state.dart` (the `memory` blackboard to write into),
      `physics/raycast.dart` + `test/raycast_test.dart` (occlusion-test
      pattern to mirror), `component_registry.dart`,
      `ai/follow_behavior.dart` (structural template for
      `InvestigateBehavior`); doc `docs/concepts/agent-api.md`.

## New engine features (v2 — suggested, not yet scoped)

- [ ] **TileMap collision layers / collision groups** — Different entities collide with different tile sets (player vs enemies vs projectiles). Extends `TileMap` with per-tile collision group bitmasks and adds `Collider.collisionGroup` / `collisionMask`.

- [ ] **Platformer-aware NavMesh / A* pathfinding** — Current pathfinding is tile-based (basic A* in `pathfinding.dart`, `PathFollowBehavior` exists); need a platformer-aware pathfinder that handles jumps, one-way platforms, ladders, and moving platforms. Output: sequence of `PathPoint` with `jumpRequired` flags consumable by a `PathFollowBehavior`.

- [ ] **Behavior Tree / State Machine** — Replace ad-hoc `Behavior` implementations with a serializable BT/FSM. Nodes: Sequence, Selector, Parallel, Decorator (Inverter, Repeater), Leaf (custom `Behavior`). Visual editor export → JSON → runtime interpreter.

- [ ] **Dialogue system enhancements** — Variables/conditions in dialogue (`{if has_sword}...`), branching by inventory/flags, localized audio per line, portrait sprites, typewriter effect, skip/replay.

- [ ] **Particle system upgrades** — Emitters attached to entities (follow Position), attractors/repellers (gravity wells, wind), GPU instanced particles via single draw call, emission shapes (circle, rect, edge), collision with TileMap.

- [ ] **Save/load system enhancements** — Version migration (`GameState.migrationVersion`), screenshot thumbnails, checksum validation, cloud sync hook. (Base `SaveGame`, `SaveSlotMenuScene` exist.)

- [ ] **Cutscene / Timeline system enhancements** — Visual editor, more step types (`MoveCamera`, `SpawnEntity`, `PlaySound`, `SetFlag`). Base `CinematicSystem` with `WaitStep`, `CallbackStep`, `TweenStep`, skip support exists.

- [ ] **Input remapping / Gamepad improvements** — Dead zones, vibration (haptics), multiple local players (split-screen), virtual gamepad layout editor, Steam Input / SDL gamepad DB integration. (Base `GamepadController`, bindings storage, haptic feedback exist.)

- [ ] **2D Normal mapping / Sprite lighting** — Normal map atlas per sprite, per-pixel lighting with depth (parallax occlusion optional). `Sprite.normalAtlasId` + `Light2D` reads normal for Lambertian shading.

- [ ] **Audio: Spatial audio / Occlusion** — Distance attenuation (inverse square / linear), low-pass filter behind walls (reuse `hasLineOfSight`), reverb zones, Doppler for moving sources.

- [ ] **Camera shake enhancements** — One-time impulse (explosion) vs sustained (earthquake), frequency/amplitude/decay params, per-axis control, additive stacking. (Basic `camera.shake(magnitude, duration)` exists.)

- [ ] **TileMap auto-tile bitmask preview** — Debug overlay showing computed bitmask per cell, hover tooltip with neighbor mask. (Bitmask logic `autotileBitmask` exists.)

- [ ] **ECS query caching / Archetypes** — Hot loops (`MovementSystem`, `CollisionSystem`) iterate archetype tables instead of sparse sets. Cache invalidation on component add/remove.

- [ ] **Job system / Multithreaded systems** — Offload `TileCollisionSystem` broadphase, `Pathfinding`, `ParticleSystem` to background isolates. Main thread only commits results.

- [ ] **Visual Behavior Tree editor (web)** — Browser-based node graph editor exporting BT JSON, loads into engine at runtime. Drag-drop nodes, live preview.

- [ ] **Procedural level generation** — Room/corridor (BSP), cellular automata caves, wave-function collapse for tile patterns. Seeded, deterministic, JSON output.
