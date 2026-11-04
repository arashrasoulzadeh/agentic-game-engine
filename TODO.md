# Remaining work

The single source of truth for what is left. Only open work lives here; delete items once shipped —
what shipped is recorded in [CHANGELOG.md](CHANGELOG.md); reasoning lives
in git history. Add newly discovered work here rather than in comments or
side files.

Related (not task lists):
- [docs/studio/design.md](docs/studio/design.md) — studio PRD / design / delivered phases
- [docs/concepts/turn-based-strategy.md](docs/concepts/turn-based-strategy.md)
- [engine_mcp.md](engine_mcp.md) — agent API (phases 0–7 shipped; add ops via
  `zarvan_core` groups + `gen_api_docs.dart`)

Per-area lists live next to what they track: studio in
[docs/studio/studio.md](docs/studio/studio.md), and the sample games in
`mobarez/mobarez_todo.md` and `zahaak/zahaak_todo.md` (both folders are gitignored,
so those files exist only on the owner's machine).

Sections: [Release](#release) ·
[Wanted: engine gaps](#wanted-engine-gaps) ·
[Parked decisions](#parked-decisions)

## Release

- [ ] After the release exists, tell downstream projects `World.storeOf` is gone
      (see [docs/migrating-from-storeof.md](docs/migrating-from-storeof.md)); it was removed
      before the tag at the owner's request.
- [ ] Cut the first public release (the local `v0.1.0` tag is 600+ commits stale, retag at `main`), decide tag/`ref`
      policy for generated projects, publish packages to pub.dev (drops the
      self-referencing git-dep constraint), then swap README badges to
      pub.dev version badges. Checklist: [docs/engine-releasing.md](docs/engine-releasing.md).

## Wanted: engine gaps

Ten things a general 2D engine needs that this repo did not have (the first six shipped (post-processing partly), plus level mechanics and were removed from
this list, see the changelog; three remain). Each was checked against the source (no
matching class or file in `zarvan_core`, `zarvan_flutter`, `zarvan_platformer` or `zarvan_strategy`) before being
listed. Tick them off as they ship, with a test and docs.

- [ ] **Shader post-processing: bloom, chromatic aberration, pixelate.** Colour grade, vignette and scanlines
      ship as `PostProcessed`; these three need fragment programs (and a captured scene texture).
- [ ] **Screen-reader semantics.** Expose menus, buttons and HUD text to TalkBack/VoiceOver (`Semantics`) from the
      engine's UI scenes; accessibility settings exist, assistive-technology support does not.
- [ ] **UI toolkit: Flutter widgets for the new models.** `layoutStack`, `anchorRect`, `ScrollListModel` and
      `TextInputModel` exist as pure models; scenes still need widgets that render and drive them.
