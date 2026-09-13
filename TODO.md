# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

Everything completed through the "New engine features"/`lib/src/`
restructure streak has been cleared from this file — see
[CHANGELOG.md](CHANGELOG.md) for what shipped and git history for the
full why behind each change.

## v1.0 release readiness

Not feature work — what an actual 1.0 tag needs beyond "the features
in this file are done." An engine can ship 1.0 with a smaller, stable
feature set; it can't ship without these. Checked directly against the
repo, not from memory.

- [x] `LICENSE` file: MIT, at the repo root plus a copy in each of the
      four packages (`packages/*/LICENSE`) since pub.dev's per-package
      publish validation looks for a `LICENSE` in that package's own
      root, not just the repo root.
- [x] `pubspec.yaml` metadata: added `homepage`/`repository` (both
      pointing at the GitHub repo) to all four packages. No `license:`
      field added — that's not a real pub.dev-recognized pubspec key;
      pub.dev auto-detects license from the `LICENSE` file above.
- [ ] API stability commitment: pre-1.0 this repo has made real
      breaking changes freely (e.g. `resolveSolidCircleAabb` returning
      a `CollisionSide` enum instead of a `bool`) — 1.0 means promising
      semver going forward, so decide what's "stable public API" vs.
      still-experimental before the tag, not after.
- [ ] Root-level getting-started walkthrough: per-package READMEs exist
      and are good API references, but nothing currently walks a
      brand-new user through `game_agent create` → running the result,
      start to finish, in one place.
- [ ] Malformed-input robustness: a published engine gets fed level/
      save JSON by people (or agents) who don't fully control it —
      worth a real pass confirming `Level.loadInto`/`TileMap.fromJson`/
      save-load fail with a clear, catchable error on garbage input
      rather than crashing, instead of assuming they already do.

## Tooling / release

- [ ] Publish `engine_core`/`engine_flutter`/`engine_cli` to pub.dev —
      removes the git-ref-matching constraint entirely via normal semver
- [ ] Test on a real Android/iOS device (or at least a release build) —
      everything so far has only been verified on Flutter web debug
      builds; orientation lock, lifecycle pause/resume, and real-world
      performance are unverified outside that

## Features (engine_flutter)

- [ ] Real masking/clipping: z-index only reorders draw *calls*; it has
      no clip-path or blend-mode primitive, so it can't express "this
      shape cuts a hole in what's behind it" or "this layer only shows
      through a mask shape." Would need its own API (e.g. a `Mask`/
      `ClipShape` component and a `Canvas.clipPath`/`saveLayer`+
      `BlendMode.dstIn` pass in `EngineView`) — worth doing once there's
      a concrete use case (fog-of-war reveal, a vignette, a wipe
      transition).

## New engine features (round 2)

Gaps identified in a follow-up pass once the previous "New engine
features" streak (text rendering, debug viz, raycasting, AI depth,
HUD/UI, folder restructure) landed — grouped by which package each
belongs in.

### Core (`engine_core`)

- [ ] Multi-layer / animated tiles: `TileMap` is single-layer with no
      per-tile animation (torches, water) — most real levels want at
      least a background/foreground layer split.
- [ ] Deterministic RNG + replay/record: no seeded RNG helper and no
      input-replay capture exist yet, both of which matter for
      reproducible testing/debugging of an agent-driven or
      physics-heavy game.
- [ ] Save-schema versioning: `GameState`/`World.toJson()` have no
      migration story — a save from an older build shape just breaks.
- [ ] Spatial range queries: `spatial_hash.dart` backs `CollisionSystem`
      internally but isn't exposed for general "what's near this
      point/rect" queries (useful for AI perception, area-of-effect).
- [ ] Multi-component query helper: `WorldView.entitiesWith<T>()` only
      filters on one component type — "every entity with both X and Y"
      still means hand-nesting a loop plus null-checks per call site;
      a real ECS this size usually wants `entitiesWithAll<A, B>()` (or
      similar) as a first-class query.
- [ ] Priority-queue-backed pathfinding open set: `findPath`'s open set
      is a linear-scan sorted list, documented as "fine at the scale a
      single AI pathfind needs" — true today, but worth swapping for a
      real binary heap once a game actually runs pathfinding at a scale
      (many simultaneous agents, or large maps) where that shows up on
      a profile.
- [ ] Content hot-reload: no way to re-load a level/`GameConfig` JSON
      file into a running `World` without a full app restart — this
      engine markets itself as agent-friendly/iteration-friendly, and
      fast content-edit-see-result loops are a big part of that promise
      that isn't delivered yet.

### Rendering (`engine_flutter`)

- [ ] Multi-line / wrapped `Text`: currently single-line only, no
      wrapping or rich formatting.
- [ ] Tile culling for large maps: `_collectTileMapItems` walks every
      tile every frame regardless of camera viewport — fine at current
      map sizes, will matter once levels get big.
- [ ] 9-slice sprites: needed for resizable UI panels/dialog boxes;
      `Sprite` is fixed-region only today.
- [ ] Fixed-timestep + render interpolation: physics and rendering
      currently share one `dt` — smooth motion at low/uneven frame
      rates wants these decoupled.
- [ ] Basic 2D lighting: no dynamic-light concept at all today (a torch
      glow, a flashlight cone, ambient darkness) — every game that
      wants mood lighting has to fake it with `Sprite`s.
- [ ] Localization / i18n: `Text` takes a raw string with no string-
      table or locale-aware font-fallback concept — every UI string a
      game shows is hardcoded English today.
- [ ] Animation clip transitions: `AnimationSystem` hard-cuts to a new
      clip's frame 0 the instant `AnimationState.clip` changes — no
      crossfade/blend between e.g. idle and walk, which reads as a
      visible pop on faster-paced games.

### Platformer (`engine_platformer`)

- [ ] Ladders/climbing, conveyors, per-tile friction: collision is
      binary solid/one-way/slope today — no variable surface behavior.
- [ ] Hitstun/knockback on damage: `damageEntity` changes health but
      nothing pushes the entity back or freezes input briefly.
- [ ] Steering/avoidance among multiple AI: `PatrolBehavior`/
      `FollowBehavior`/`PathFollowBehavior` don't avoid each other, so
      packs of enemies overlap/stack.
- [ ] Variable jump height (jump-cut): every other jump-feel primitive
      (coyote time, buffering, double jump, wall jump, dash) already
      exists, but releasing the jump button early doesn't shorten the
      jump — `JumpSystem` always applies the full `jumpSpeed` for the
      whole arc, so there's no way to do a quick hop vs. a full-height
      jump with one input.
- [ ] Ledge grab / mantle: no way for an entity near the top of a wall
      at the peak of a jump to grab on and climb up — every ledge has
      to be cleared by a clean jump arc today, which is a common
      "genuinely complete platformer" expectation this engine doesn't
      meet yet.
- [ ] Swimming / water physics: no water-zone concept (altered gravity/
      max-fall-speed, buoyancy, a swim state distinct from walk/jump) —
      a `TriggerZone` can detect entering water, but nothing changes
      how the entity actually moves once it has.
- [ ] Boss/enemy phase framework: `CinematicSystem` can script a
      one-shot sequence and `Health`/`damageEntity` cover generic
      combat, but there's no platformer-specific helper tying the two
      together for "at 50% health, play this cinematic beat and switch
      attack patterns" — every boss fight has to hand-roll that state
      machine from scratch today.
