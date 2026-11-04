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

Ten things a general 2D engine needs that this repo does not have. Each was checked against the source (no
matching class or file in `zarvan_core`, `zarvan_flutter`, `zarvan_platformer` or `zarvan_strategy`) before being
listed. Tick them off as they ship, with a test and docs.

- [ ] **Time scale and hit-stop in the world.** `World.timeScale` (slow motion, pause groups, per-system exemption)
      so hit-stop and bullet time are one call. `zarvan_idle` fakes hit-stop by disabling named systems.
- [ ] **Entity / object pooling.** A reusable pool for bullets, particles, damage numbers and projectiles, so a busy
      scene stops allocating entities and components every frame.
- [ ] **Data-driven spawners.** Timed, wave and area spawners authored as component data (what, where, how often,
      cap, stop condition), usable by any genre; today waves exist only inside `zarvan_idle`.
- [ ] **Camera dead-zone, look-ahead and bounds.** Follow with a dead-zone window, velocity look-ahead and clamping
      to a level rectangle, on top of the existing follow and shake.
- [ ] **Joints and springs.** Distance, spring and rope constraints between entities (and entity-to-point), solved
      in a system; the only physics today is circle/AABB collision and platformer gravity.
- [ ] **Post-processing pipeline.** Full-screen shader passes (bloom, vignette, scanlines/CRT, colour grading,
      chromatic aberration, pixelate) as a component stack on the camera; today only `ScreenTint` and the lighting
      shaders exist.
- [ ] **In-game developer console.** A command console (toggle, history, autocomplete) wired to the operation
      registry so every agent operation and cheat (`give`, `teleport`, `timescale`) is typable on device.
- [ ] **Screen-reader semantics.** Expose menus, buttons and HUD text to TalkBack/VoiceOver (`Semantics`) from the
      engine's UI scenes; accessibility settings exist, assistive-technology support does not.
- [ ] **UI toolkit pieces: text input, scrolling lists, layout containers.** In-world UI has buttons and menus but
      no text field, scroll view or row/column/anchor layout.
- [ ] **Level mechanics: conveyors, teleporters, destructible tiles.** Data-driven tile and trigger behaviours beyond
      one-way and moving platforms, with editor-schema support so the studio can place them.

Also noted, smaller: minimap, trail/ribbon renderer, weather particle presets, in-game toast queue.

## Parked decisions

Not tasks — conclusions kept so they aren't re-litigated. Re-open only on
the stated trigger.

- **No dirty-rect / partial redraw in `EngineView`.** Full redraw every
  tick is deliberate; measured paint is ~10–16% of frame on device.
  **Re-open only** if `paint` itself becomes a real over-budget fraction.
- **No 3D, ever** and **no other game engines** — see CLAUDE.md.
- **Networking stops at `NetEndpoint`.** WebRTC / NAT traversal need a
  native plugin or relay; games wire that themselves.
- **Published samples are the three `zarvan create` templates** (CI
  builds each). No sample app in this repo (`test_game/` stays gitignored).
- **Docs stay single-version** until the first published release; then
  consider `mike` with the v0.1.0 tag. `proposals/` and
  `studio/qa-level-editor.md` stay unpublished on purpose.
- **`PlayerOptions` stay shell-applied.** The engine stores/presents settings
  but does not read them itself. Games wire `colorblindMode` /
  `screenShakeIntensity` (templates zero shake when `reduceMotion`), volumes,
  and `textScale` in their own UI. Re-open only if a second genre needs the
  same wiring and duplication becomes painful — see
  [docs/concepts/settings.md](docs/concepts/settings.md).
