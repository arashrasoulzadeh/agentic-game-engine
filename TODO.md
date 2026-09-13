# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

Everything completed through the "New engine features"/`lib/src/`
restructure streak has been cleared from this file — see
[CHANGELOG.md](CHANGELOG.md) for what shipped and git history for the
full why behind each change.

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
