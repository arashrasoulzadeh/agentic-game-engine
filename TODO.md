# Remaining work

The single source of truth for what is left. Only open work lives here; delete items once shipped —
what shipped is recorded in [CHANGELOG.md](CHANGELOG.md); reasoning lives
in git history. Add newly discovered work here rather than in comments or
side files.

Related (not task lists):
- [docs/studio/design.md](docs/studio/design.md) — studio PRD / design / delivered phases
- [docs/concepts/turn-based-strategy.md](docs/concepts/turn-based-strategy.md)
- [engine_mcp.md](engine_mcp.md) — agent API (phases 0–7 shipped; add ops via
  `engine_core` groups + `gen_api_docs.dart`)

Per-area lists live next to what they track: studio in
[docs/studio/studio.md](docs/studio/studio.md), and the sample games in
`mobarez/mobarez_todo.md` and `zahaak/zahaak_todo.md` (both folders are gitignored,
so those files exist only on the owner's machine).

Sections: [Performance](#performance) ·
[Template health](#template-health) · [Docs](#docs) · [Release](#release) ·
[Parked decisions](#parked-decisions)

## Performance

- [ ] **GPU shadows on device** — `Light2D.useGpuShadows` stays `false`;
      overlapping lights saturated to white with `BlendMode.plus`. Candidate
      fix already in tree (`BlendMode.screen` on the GPU pass). Confirm on a
      real release APK; if good, enable on `test_game` torches and drop the
      KNOWN BUG note on `Light2D.useGpuShadows`. If not, try shrinking
      `light_shadow.frag`'s flat `falloff` plateau next (not a multi-light
      shader rewrite until this is settled).
- [ ] **Idle device bench** — host baseline is in
      `packages/engine_idle/benchmark/idle_bench.dart` (2026-10-25). Still need
      release-APK timings for ~1,000 generators and long offline catch-up.

## Template health

- [ ] The templates job now also runs on `engine_core`/`flutter`/`platformer`/`idle`/`schema`
      changes (it used to run only for CLI and strategy edits, so engine API breaks went
      unnoticed) and can be started by hand. `game_agent create` needs pub.dev, so it
      cannot run in the offline dev sandbox; confirm the job is green on `main`.

## Docs

Site: <https://meetarash.ir/agentic-game-engine/>.

- [ ] Strategy-template screenshot (needs art); `UPDATE_SCREENSHOTS=1` regenerates `docs/img/`.

## Release

- [ ] After the release exists, tell downstream projects `World.storeOf` is gone
      (see [docs/migrating-from-storeof.md](docs/migrating-from-storeof.md)); it was removed
      before the tag at the owner's request.
- [ ] Cut the first public release (the local `v0.1.0` tag is 600+ commits stale, retag at `main`), decide tag/`ref`
      policy for generated projects, publish packages to pub.dev (drops the
      self-referencing git-dep constraint), then swap README badges to
      pub.dev version badges. Checklist: [docs/engine-releasing.md](docs/engine-releasing.md).

## Parked decisions

Not tasks — conclusions kept so they aren't re-litigated. Re-open only on
the stated trigger.

- **No dirty-rect / partial redraw in `EngineView`.** Full redraw every
  tick is deliberate; measured paint is ~10–16% of frame on device.
  **Re-open only** if `paint` itself becomes a real over-budget fraction.
- **No 3D, ever** and **no other game engines** — see CLAUDE.md.
- **Networking stops at `NetEndpoint`.** WebRTC / NAT traversal need a
  native plugin or relay; games wire that themselves.
- **Published samples are the three `game_agent create` templates** (CI
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
