# Remaining work

The single source of truth for what is left. Delete items once shipped —
what shipped is recorded in [CHANGELOG.md](CHANGELOG.md); reasoning lives
in git history. Add newly discovered work here rather than in comments or
side files.

Related (not task lists):
- [docs/studio/design.md](docs/studio/design.md) — studio PRD / design / delivered phases
- [docs/concepts/turn-based-strategy.md](docs/concepts/turn-based-strategy.md)
- [engine_mcp.md](engine_mcp.md) — agent API (phases 0–7 shipped; add ops via
  `engine_core` groups + `gen_api_docs.dart`)

Sections: [Performance](#performance) · [Engine](#engine) · [Studio](#studio) ·
[Docs](#docs) · [Release](#release) · [Parked decisions](#parked-decisions)

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

## Engine

- Idle / incremental genre is complete for creating new games
  (`game_agent create --template idle_game`, full subsystem table in
  [docs/concepts/idle-games.md](docs/concepts/idle-games.md)). Only the
  device bench under Performance remains for idle.
- [ ] **Zahaak gaps** — features that local `zahaak` needs but the engine
      lacks (`zahaak/docs/engine-gap-analysis.md`). Not scoped; revisit once
      its combat/dialogue scope is locked.

## Studio

Design and delivered phases: [docs/studio/design.md](docs/studio/design.md).

- [ ] **Distribution (3.22)** — stand-in `.dmg` packing is CI-checked
      (`tool/verify_dmg_pack.sh`). Still open: real
      `flutter build macos --release` (FlutterMacOS.framework arch check failed
      here), `.msi` / `.AppImage`, code signing + notarization, and a release
      server / signing key (update client exists; nothing to talk to).
- [ ] **Debugger and terminal** — each its own phase; not in current IDE scope.

## Docs

Site: <https://meetarash.ir/agentic-game-engine/>.

- [ ] Strategy-template screenshot (needs art) and a studio shot with real
      entity-label text (`UPDATE_SCREENSHOTS=1` regenerates `docs/img/`).
- [ ] Decide whether `reduceMotion` / text scale etc. should be engine
      behaviour (`PlayerOptions` is not read by the engine today).

## Release

- [ ] Cut the first public release: push local `v0.1.0`, decide tag/`ref`
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
- **Studio stretch not scheduled:** separate play-test process profiling,
  live cursor feed, visual three-way merge UI (`studio merge` covers CLI).
