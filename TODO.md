# Remaining work

The single source of truth for what is left. Delete items once shipped —
what shipped is recorded in [CHANGELOG.md](CHANGELOG.md); reasoning lives
in git history. Add newly discovered work here rather than in comments or
side files.

Related (not task lists):
- [docs/studio/design.md](docs/studio/design.md) — studio PRD / design / delivered phases
- [docs/concepts/turn-based-strategy.md](docs/concepts/turn-based-strategy.md)
- [engine_mcp.md](engine_mcp.md) — agent-API design (phases 0–7 shipped)

Sections: [Performance](#performance) · [Engine](#engine) ·
[Agent API](#agent-api) · [Studio](#studio) · [Docs](#docs) ·
[Release](#release) · [Parked decisions](#parked-decisions)

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

- [ ] **Zahaak gaps** — features that local `zahaak` needs but the engine
      lacks (`zahaak/docs/engine-gap-analysis.md`). Not scoped; revisit once
      its combat/dialogue scope is locked.

## Agent API

Shipped (see CHANGELOG / `engine_mcp.md`): phases 0–7, full operation
catalogue, MCP/HTTP/JSON-RPC, SSE progress/cancel, request-log levels,
`studio` edit → `level.*` adapters, transports quick start.

**Adding an operation:** implement in `engine_core/lib/src/ops/groups/`,
register in `all_operations.dart` + `engine_core_ops.dart`, test under
`engine_core/test/ops/`, then regenerate
`docs/reference/operations.md` and `docs/reference/transports.md` via
`packages/engine_api/tool/gen_api_docs.dart`.

## Studio

Design and delivered phases: [docs/studio/design.md](docs/studio/design.md).
M0–M2 and most of the code-editor / stretch work are done.

- [ ] **Distribution (3.22)** — stand-in `.dmg` packing is CI-checked
      (`tool/verify_dmg_pack.sh`, `diskutil` / `hdiutil` fallback). Still open:
      real `flutter build macos --release` (FlutterMacOS.framework arch check
      failed here), `.msi` / `.AppImage`, code signing + notarization, and a
      release server / signing key (update client exists; nothing to talk to).
- [ ] **Debugger and terminal** — each its own phase; not in current IDE
      scope (`pub get` and git status marks are done).
- [ ] Optional: profile a separate play-test process (no channel yet);
      live cursor feed; visual three-way merge UI (`studio merge` covers CLI).

## Docs

Site: <https://meetarash.ir/agentic-game-engine/>. Conventions in
[docs/contributing-docs.md](docs/contributing-docs.md). Coverage gaps for
shipped features are closed.

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
  native plugin or relay; games wire that themselves. WebSocket, UDP,
  lobby, host auth, and `OnlineStrategyView` are shipped.
- **Published samples are the three `game_agent create` templates** (CI
  builds each). No sample app in this repo (`test_game/` stays gitignored).
- **Docs stay single-version** until the first published release; then
  consider `mike` with the v0.1.0 tag. `proposals/` and
  `studio/qa-level-editor.md` stay unpublished on purpose.
