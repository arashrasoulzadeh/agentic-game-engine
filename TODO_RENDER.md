# Rendering topics to come back to

Separate from [TODO.md](TODO.md) — parked discussion points about the
rendering architecture specifically, not yet scoped into actionable
work items.

## Full-screen repaint every frame — no dirty-rect/partial redraw

`EngineView`'s painter (`_EnginePainter` in
`packages/engine_flutter/lib/src/rendering/engine_view.dart`) has
`shouldRepaint` hardcoded to always return `true`
(`engine_view.dart:1611`). Every tick, the *entire* draw pipeline
re-runs from scratch — background/parallax, every tile, every sprite,
every particle, the whole lighting pass — regardless of whether
anything on screen actually changed. There is no dirty-rect tracking,
no "only redraw the region a moving sprite touched" logic anywhere.

Confirmed deliberate, not an oversight, for this kind of engine:

- A 2D game with a moving camera invalidates most of the visible area
  almost every frame anyway (panning/scrolling, animated tiles,
  flickering torches, particles) — dirty-rect tracking would rarely
  save much in practice here while adding real bookkeeping cost and
  bug surface (tracking exactly which screen regions each of dozens of
  entity types touched, across the whole draw-order/z-index system).
- GPUs are fast at full-canvas 2D redraws; this is the standard
  approach most Skia/Impeller-backed engines in this weight class use.
- Viewport culling (an off-screen light/tile skipped *before* its
  expensive work runs) already exists and is the right lever for
  "don't do wasted work" in this architecture — it's a different
  mechanism from dirty-rect redraw and doesn't require it.

Also relevant: `EngineView`'s existing `saveLayer`+`dstOut`
ambient-lighting overlay (see [TODO.md](TODO.md)'s Performance
section) is a separate, already-tracked cost specific to the lighting
pass, not the same issue as this one.

**Measured, not just reasoned about (2026-09-16)**: real
`debugPrint('DIAG $frameStats')` output from `test_game`'s prison
level, a genuine **release APK on a real Android device**
(`SM S731B`), captured via `adb logcat` over ~25s of actual gameplay
(camera panning, ~24 sprites, ~45-50 active particles, the full
lighting pass all live):

```
DIAG frame: 8.34ms  step: 0.11ms  paint: 0.88ms  light: 0.11ms  ...
DIAG frame: 8.28ms  step: 0.09ms  paint: 0.93ms  light: 0.10ms  ...
DIAG frame: 8.32ms  step: 0.07ms  paint: 1.28ms  light: 0.19ms  ...
DIAG frame: 8.34ms  step: 0.09ms  paint: 1.05ms  light: 0.33ms  ...
```

`paint` — the *entire* full-screen repaint this section is about,
tiles/sprites/particles/lighting all included — consistently costs
**0.85-1.3ms**, against an ~8.3ms total frame budget (this build runs
capped near 120fps). That's ~10-16% of budget spent fully redrawing
everything from scratch every tick, comfortably inside it, with
`light` (the ambient/shadow pass — the actual tracked cost in
`TODO.md`'s Performance section) a further ~0.1-0.3ms on top.

**Conclusion**: this is not a bottleneck in this game, full stop —
confirmed by measurement, not just the reasoning above. No dirty-rect
work is justified here. Re-open only if a future scene profile (many
more entities, a much larger visible tile area, etc.) shows `paint`
itself becoming a real fraction of a frame that's actually over
budget — not before.
