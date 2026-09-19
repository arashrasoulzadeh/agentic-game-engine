# Proposal: per-frame animation events + a visual animation IDE

Status: draft, not implemented. Written against the **current** JSON
schema (`AnimationClip`, atlas manifests, level JSON) rather than a new
bundled container format — see "Why not a new `.gsp` format" below.

## Problem

Today, wiring up a character's animation set means hand-editing JSON:
cropping regions with the sprite-sheet cutter, copying region names
into `frameRegions`, and computing `frameOffsetsY` by hand (subtract
frame height from a reference height — see
[`AnimationClip`'s doc comment](../../packages/engine_flutter/lib/src/rendering/animation.dart)).
There is no way to say "play this sound effect on frame 4 of the
attack swing" or "enable the hit-box only between frames 4 and 6"
without writing bespoke Dart in `_AttackAnimationSystem`-style code
per game. That logic is currently baked into `test_game`'s scene code
frame-index-by-frame-index (`if (state.frameIndex == 4) { ... }`),
which is exactly the kind of thing that should be data.

## Design: `AnimationClip.events`

Add one new optional field to `AnimationClip`, alongside
`frameOffsetsX`/`frameOffsetsY` — same pattern, same backward
compatibility (`null` default, existing clips unaffected, `assert`
checks it only where non-null):

```dart
class AnimationClip {
  // ...existing fields...
  final List<List<AnimationEvent>>? frameEvents;
}

class AnimationEvent {
  final String type;   // 'sfx' | 'hitbox_on' | 'hitbox_off' | 'particle' | ...
  final Map<String, dynamic> data; // type-specific payload, e.g. {'id': 'footstep_l'}
}
```

`frameEvents[i]` is the list of events that fire the instant playback
*enters* frame `i` (empty list for most frames). Indexed identically
to `frameRegions`, exactly like the offset arrays.

JSON shape (additive to the existing clip JSON):

```json
{
  "name": "attack",
  "frameRegions": ["attack_0", "attack_1", "attack_2", "attack_3"],
  "frameDurationSeconds": 0.06,
  "loop": false,
  "frameOffsetsY": [0, -2, -2, 0],
  "frameEvents": [
    [],
    [],
    [{"type": "hitbox_on", "data": {}}],
    [{"type": "sfx", "data": {"id": "sword_swing"}}, {"type": "hitbox_off", "data": {}}]
  ]
}
```

### Firing events: `world.events`

`engine_core` already has a generic pub/sub bus
([`event_bus.dart`](../../packages/engine_core/lib/src/ecs/event_bus.dart),
the same one `DamageEvent`/`DeathEvent` use). `AnimationSystem` is the
natural place to emit — it already knows exactly when `frameIndex`
changes:

```dart
// inside AnimationSystem.update, right after state.frameIndex = nextIndex (or 0):
final events = clip.frameEvents?[state.frameIndex];
if (events != null) {
  for (final e in events) {
    world.events.emit(AnimationFrameEvent(entity, clip.name, e.type, e.data));
  }
}
```

This keeps `AnimationSystem` genre-general (it doesn't know what
"sfx" or "hitbox_on" *mean* — it just emits a typed event) and lets
`engine_platformer`/`engine_flutter`/game code subscribe:

- A **new, small `engine_flutter` system** (e.g. `AnimationSfxSystem`)
  subscribes to `AnimationFrameEvent` where `type == 'sfx'` and calls
  `AudioManager.playSound(data['id'])` (or a positional variant using
  the entity's `Position`, mirroring `playPositionalSound`). This
  finally makes "sfx and their play times on frame index" (your
  phrase) a data-driven feature instead of scene code.
- `engine_platformer`'s combat code subscribes to `hitbox_on`/
  `hitbox_off` to gate `AttackSystem`'s existing melee-range check
  instead of the current fixed `meleeDurationSeconds` window —
  this is a genuine improvement (frame-accurate hit windows instead
  of a wall-clock timer) but is a separate, larger change to
  `combat_helpers.dart` and shouldn't be bundled into the same PR as
  the event plumbing itself.
- Anything else (particles, screen shake, camera punch) is just
  another `type` string — no engine change needed once the dispatch
  mechanism exists, which is the actual point of making this generic
  rather than hardcoding an `sfxId` field like a first draft might.

### Pivots — no new mechanism needed

You called out pivots specifically: these are exactly
`frameOffsetsX`/`frameOffsetsY`, which already exist. No new field —
the IDE just needs a UI for the thing the engine already supports (see
below).

### World-unit-relative sizing

Your note "sizes based on world size that is 1" — `Sprite.scaleX`/
`scaleY` already do this (a region's raw pixel size × scale = world
units), and pivots (`frameOffsetsX`/`frameOffsetsY`) are already
specified in the *same unscaled atlas-pixel space* as the region
itself, then scaled by `sprite.scaleX`/`scaleY` at draw time (see
[`engine_view.dart`](../../packages/engine_flutter/lib/src/rendering/engine_view.dart)'s
`anchorPos` computation). So this constraint is already satisfied by
the current design — worth stating explicitly in the IDE spec so
nobody re-derives a second scaling scheme.

### Multiple "event animations"

Read as: more than one animation can define events, and multiple
distinct animations (walk, attack, death) each carry their own
`frameEvents`. That's already the shape above — `frameEvents` lives on
each `AnimationClip`, so `movementAnimationSet.walk` and a
`enemyAttackClip` each have independent event tracks. Nothing extra
needed here beyond the field itself.

## Why not a new `.gsp` bundle format (for now)

A zip container (spritesheet + manifest + sfx as one file) is still a
reasonable idea for later, but two things argue for deferring it:

1. **Migration cost vs. payoff right now.** Every existing level JSON,
   manifest, and the sprite-sheet cutter Artifact already speak the
   current per-field JSON shape. A new container format means an
   import/export step and two formats to keep in sync for no
   functional gain yet — the events feature above doesn't need it.
2. **The IDE is the part that actually needs solving.** Once an IDE
   exists that edits regions/clips/pivots/events against the *current*
   JSON files directly, adding a "package as .gsp" export button is a
   small additive feature on top of a working tool, not a prerequisite
   for one. Building the container first would mean designing file
   packing/unpacking before there's any tool that benefits from it.

Recommendation: ship `frameEvents` + the dispatch systems first (pure
engine feature, small, testable, unblocks the IDE's most-requested
capability), build the IDE against current files, and revisit `.gsp`
as an export format once the IDE's own save/load path is proven.

## The IDE

A second Flutter desktop app (reuses `engine_flutter`'s own
`AtlasRegistry`/`EngineView` for pixel-accurate live preview — no
second rendering implementation to keep in sync with the engine).

**Screens / panels:**

1. **Sheet importer + region cutter** — already prototyped as the
   "Sprite Sheet Cutter" web Artifact (canvas-based select/add/resize,
   live-regenerating region JSON). The IDE's version is the same
   interaction model, now able to write directly to a manifest file on
   disk instead of a copy-paste JSON panel.
2. **Clip editor** — pick an ordered list of regions into a named
   clip, set `frameDurationSeconds`/`loop`.
3. **Timeline** — horizontal frame strip (thumbnail per frame from the
   already-cropped region). Scrub to preview via a live `EngineView`
   instance running just that one entity/clip.
4. **Pivot tool** — click-drag a crosshair on the live preview canvas
   per frame; writes `frameOffsetsX/Y[i]`. Onion-skinning (ghost the
   adjacent frame) makes it obvious when a pivot is off, which is
   exactly the bug this session spent real time hunting by eye
   (see the walk-animation-floats-above-ground fix earlier in this
   project's history) — this is the single highest-value IDE feature
   given that history.
5. **Event track** — a lane under the timeline per event type
   (sfx / hitbox / particle / custom); click a frame cell to attach an
   event, edit its `data` payload in a side panel. SFX events get a
   file picker + inline playback preview.
6. **Save** — writes back into the existing manifest/level JSON
   structure in place (no new file format, per above), with a diff
   preview before overwrite so a hand-edited level file doesn't get
   silently reformatted/reordered.
7. **Playtest button** — drops the edited entity into a minimal
   `World` and runs it live in an embedded `EngineView`, so pivot/event
   timing is checked against actual physics/animation-system tick
   behavior, not just the static timeline preview.

**Scope note:** this is a multi-week build, not a quick add-on — it's
effectively a second application depending on `engine_flutter`. Doesn't
need to be built in one pass: the cutter (already exists as an
Artifact) → clip editor → pivot tool → event track is a natural
incremental order, each step independently useful before the next
exists.

## Suggested implementation order

1. `AnimationEvent`/`AnimationClip.frameEvents` + `AnimationFrameEvent`
   on `world.events`, emitted from `AnimationSystem` — engine_core/
   engine_flutter, fully tested, no IDE dependency.
2. `AnimationSfxSystem` in `engine_flutter` (or `engine_platformer` if
   it needs combat context) subscribing to `sfx` events.
3. Docs + example recipe (`docs/examples/animation-events.md`) showing
   the JSON shape and the subscribe pattern, same treatment as the
   other example recipes.
4. IDE, starting from the existing cutter Artifact as the seed for
   panel 1.
