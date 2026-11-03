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

Sections: [Performance](#performance) · [Engine](#engine) ·
[Template health](#template-health) · [Mobarez](#mobarez-sample-follow-ups) ·
[Studio](#studio) · [Docs](#docs) · [Release](#release) ·
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

## Engine

- [ ] **Zahaak remainder** — combat/dialogue/boss/combo/parry/guard FSM
      already ship in `engine_platformer` / `engine_flutter` (see refreshed
      `zahaak/docs/engine-gap-analysis.md`). Still open: Persian font bundling
      in the game itself, and rewriting GDD §11 from Unity → this ECS once
      zahaak build scope locks.

## Template health

- [ ] **`game_agent create` against the pushed ref (G6)** has not been run by hand
      since the last engine changes; CI's `engine_cli` templates job last ran green
      on `0209dc8`.
- [ ] **Flaky studio test** — `play_test_test.dart` "devices and stopping the
      device in use appears in the launch arguments" failed once in CI with
      "failed after test completion" (a timer or stream outliving the test).
- [ ] CI's templates job is the only automatic check that templates compile and pass their own tests; run a scratch
      `game_agent create` for each template locally when you change a template or the engine API.

## Mobarez sample follow-ups

The sample is now a config plus a JSON level on `WaveCombatScene`. Open:

- [ ] Express the level as an engine `LevelDocument` (`Level.loadInto`) instead
      of the custom `LevelData` JSON, so it is editable in Studio and by agents.
- [ ] Wire audio: `AudioManager` plus `installAnimationCueSystems(audio:)` sfx cues
      on attack/hit/death frames.
- [ ] Menus, settings and save slots from the engine's menu scenes.
- [ ] Use `ParticleEmitter`/cue bursts for the walk dust; hero `special` sheet
      (needs a larger cell than 128).

## Studio

Design and delivered phases: [docs/studio/design.md](docs/studio/design.md).

- [ ] **Distribution (3.22)** — stand-in packing is CI-checked for macOS
      `.dmg` (`tool/verify_dmg_pack.sh`), Linux AppDir/AppImage
      (`tool/verify_appimage_pack.sh`), and Windows zip/MSI hook
      (`tool/verify_windows_pack.sh`). Still open: real
      `flutter build macos --release` (FlutterMacOS.framework arch check failed
      here), WiX `.msi` authoring, `appimagetool` on release hosts, code
      signing + notarization, and a release server / signing key (update
      client exists; nothing to talk to).
- [ ] **Debugger** — own phase; not in current IDE scope.

## Engine (unsupported imports)

- [ ] Tiled import: several tilesets, external `.tsx` files and zlib/gzip-compressed
      layer data are not supported (compressed data is rejected with a hint).

## Docs

Site: <https://meetarash.ir/agentic-game-engine/>.

- [ ] Strategy-template screenshot (needs art) and a studio shot with real
      entity-label text (`UPDATE_SCREENSHOTS=1` regenerates `docs/img/`).

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
- **Studio stretch not scheduled:** separate play-test process profiling,
  live cursor feed, visual three-way merge UI (`studio merge` covers CLI).
- **`PlayerOptions` stay shell-applied.** The engine stores/presents settings
  but does not read them itself. Games wire `colorblindMode` /
  `screenShakeIntensity` (templates zero shake when `reduceMotion`), volumes,
  and `textScale` in their own UI. Re-open only if a second genre needs the
  same wiring and duplication becomes painful — see
  [docs/concepts/settings.md](docs/concepts/settings.md).
