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

**Revisit later**: if a real, measured case ever shows this
mattering (not a hypothesis — the same rule the GPU-shadow
investigation already established for this codebase), worth exploring
whether a bounded/partial approach makes sense for a specific
sub-case (e.g. a mostly-static scene with a small HUD-only update),
rather than a general dirty-rect system for the whole renderer.
