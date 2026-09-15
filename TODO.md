# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

Everything completed through the v1.0-release-readiness pass and the
"New engine features (round 2)" streak (including its full "Rendering"
group) has been cleared from this file — see [CHANGELOG.md](CHANGELOG.md)
for what shipped and git history for the full why behind each change.
Also cleared: the real, on-device `FrameStats` diagnostic tooling and
the fps-while-moving fix it uncovered (a `VirtualJoystick` rebuilding
its entire subtree on every drag-update event) — see the "Extend
FrameStats..." and "Fix VirtualJoystick rebuilding..." commits for the
full before/after on-device evidence.

## Tooling / release

- [ ] Publish `engine_core`/`engine_flutter`/`engine_cli` to pub.dev —
      removes the git-ref-matching constraint entirely via normal semver
- [ ] Test on a real Android/iOS device — **further progress**:
      `flutter build apk --release --no-pub` for `test_game` succeeded
      against a physically connected Android device (`SM S731B`,
      Android 16, found via `flutter devices`) — 45.3MB release build,
      confirms release-mode compilation/R8 minification doesn't break
      anything (`--no-pub` needed since this sandbox blocks pub.dev
      network access; a known, established limitation, not an engine
      bug). `flutter install -d <device>` then actually installed that
      APK onto the device successfully. That device is no longer
      connected in the current environment, so launching and
      interacting with the installed app to verify orientation lock,
      lifecycle pause/resume, and real-world performance is still
      outstanding — pick this back up next time a real Android device
      is available. `flutter build ios --release --no-codesign` still
      fails on this environment's broken CocoaPods (Ruby/CocoaPods
      version mismatch) — a local sandbox issue, not an engine bug, not
      attempted to fix here since it'd mean touching system Ruby/
      CocoaPods outside this repo's scope; the iOS Simulator control
      tool available in this environment is moot while the iOS build
      itself won't compile here regardless.

## Performance optimizations

Candidate follow-ups identified while adding `pack-assets`/packed-atlas
support above, listed here per this repo's "add newly discovered work
rather than letting it go untracked" rule. Each needs its own before/
after benchmark (`packages/engine_core/benchmark/`, `packages/
engine_platformer/benchmark/`, or a new `engine_flutter` render-focused
one) before landing, per this file's own Validation section and the
code-quality-bar's "re-run the benchmark suite for anything on a hot
path" rule — none of these should be believed faster just because they
sound like they should be. Several below (bin-packing, debug-draw
batching, atlas unloading) were correctness/mechanism changes with
their own direct unit-test coverage rather than raw-throughput wins
needing a benchmark harness; the remaining open ones are either blocked
on a real design decision (mipmaps, atlas-unload *policy*) or
deliberately left unstarted because implementing them now would add
real invalidation-tracking risk for an unconfirmed win (see each one's
own note).

- [ ] Spatial-hash-based light culling — **re-evaluated with a real
      measurement, still not implemented**: `_drawLighting` already
      viewport-culls each light via `_circleIntersectsRect` before its
      expensive shadow-raycasting path, but still iterates every
      `Light2D` in the `World` every frame to do that cheap check first.
      A throwaway probe (not committed — same `flutter test`+`Stopwatch`
      technique used to re-evaluate the tile-culling/draw-item-list
      items above, 300 pumped frames) scattered 300 lights across a
      40000x40000 world with only a few landing near a static camera:
      ~0.67ms/frame with all 300 plain (non-shadow-casting), ~0.47ms/
      frame with all 300 `castsShadows: true` (most get culled before
      the expensive raycast path even runs) — both comfortably under
      3% of a 60fps frame budget at a light count (300) well past what
      any real level in this repo has used. The O(lights) arithmetic
      cull itself just isn't the bottleneck at counts that matter;
      building/maintaining a spatial hash would itself cost O(lights)
      per frame to insert/rebuild unless cached across frames, which
      reintroduces the exact invalidation-tracking risk
      `cacheShadowGeometry` already had to solve carefully — not worth
      that complexity for an unconfirmed win. Revisit only if a real
      level's profile ever shows this path actually costing something.
- [ ] `_collectTileMapItems`'s per-frame tile culling (engine_view.dart)
      recomputes the visible tile range from the camera every frame,
      correctly, but a `TileMap` that never scrolls out of view entirely
      (fits fully on screen, or the camera never moves) could instead
      cache its full `_DrawItem` list once and only invalidate on
      camera movement/zoom change — **re-evaluated with a real
      measurement, still not implemented**: the earlier blocker ("can't
      `dart run` Flutter-dependent code in this environment") turned
      out to be avoidable — `flutter test` itself can time real paint
      passes with a `Stopwatch` around repeated `tester.pump()` calls,
      the same technique `tile_rendering_test.dart`'s existing "renders
      promptly" regression guard already uses, just run across many
      frames instead of one. A throwaway probe (300 pumped frames, a
      static camera, 200 sprites) measured ~1.2ms/frame for a 40x40
      `TileMap` fully on screen (1600 visible tiles) versus ~1.0ms/frame
      for a 2000x2000 (4,000,000-tile) map culled down to the same
      visible count — statistically indistinguishable, confirming the
      existing viewport culling already makes total map size a non-
      factor, and total render cost sits comfortably under 10% of a
      60fps frame budget even in the *uncached*, worse-case-for-this-
      optimization scenario (a fully-visible, never-culled map). No
      evidence of an actual bottleneck to fix — implementing the cache
      now would be optimizing an already-cheap path on faith, the exact
      thing this file's Validation section (and the shadow-smoothing
      walkback) warns against. Revisit only if a real level's profile
      ever shows this path actually costing something.
- [ ] `EngineView`'s draw-item list (`_DrawItem`, built fresh every
      frame in `paint()` from every renderable component store) —
      **re-evaluated alongside the item above, same probe, still not
      implemented**: the same measurement (200 sprites plus the tile
      pass, same static-camera scenario) covers this path too, since
      `_DrawItem` construction runs every frame regardless of tile
      count — no signal of a bottleneck there either. The fix's own
      likely shape (a `ComponentStore` "changed since version N" check)
      would touch the write path *every* store's `set`/`get` already
      sits on — a real, ongoing cost for every future write, not a
      one-time cost — so it stays unjustified without evidence it
      actually solves a problem the engine has. Revisit alongside the
      item above.
- [ ] `World.toJson()`/full-state serialization (used for save/load and
      the agent-facing API) walks every `ComponentStore` and rebuilds a
      fresh `Map` per entity per component every call — **evaluated,
      deliberately not implemented**: this item's own original note
      already said it "needs real agent-workload evidence this is
      actually hit often enough to matter before building it," and no
      such evidence exists yet — an agent-facing polling workload at a
      rate where this would actually matter hasn't been observed, only
      hypothesized. The likely shape (dirty-tracking per entity/
      component, keyed by tick) would add write-path overhead to every
      `ComponentStore.set` call in the engine to speed up a read path
      with no confirmed frequent caller — building it now would be
      designing for a hypothetical requirement against this repo's own
      "don't add complexity for a hypothetical future requirement"
      principle, not a measured win. Revisit if/when an actual agent
      workload profile shows frequent `World.toJson()` polling costing
      something real.

## Lighting follow-ups

Reported live: a shadow-casting light's shadow visibly *flickers*
(edges popping/jittering frame to frame) while its light source is
moving, instead of the shadow sliding smoothly the way the light
itself does — fixed (see below). Also reported: lighting quality in
general "not very good" — two visual-quality items closed out
alongside the flicker fix and `blockOneWayPlatforms`, described below.
Remaining open items (entity shadow casting, additive overlap,
fixed-timestep interpolation) still need a design pass before
implementing.

- [ ] GPU-shader shadow casting — **landed as opt-in engine
      infrastructure, but has a confirmed, unresolved real-device bug —
      NOT safe to enable, `test_game` does not use it.** Reported live
      (a real Android device showed fps dropping to ~24 with a
      flickering, shadow-casting torch in camera view). Researched how
      other engines handle 2D dynamic shadow casting at scale: the
      standard technique is a GPU-based 1D polar shadow map (occluders
      rendered to an offscreen texture, unwrapped per-angle, sampled in
      a lighting shader) — a genuine ground-up rewrite with real
      cross-platform risk (no way to test iOS from this environment,
      known Flutter web fragment-shader gaps). Implemented a scoped-
      down, real variant instead: `Light2D.useGpuShadows` (`false`
      default) draws a GPU-shader point light
      (`shaders/light_shadow.frag`) doing per-pixel ray-vs-line-segment
      occlusion tests against nearby solid `TileMap` boundary edges (up
      to 32, nearest-first), replacing the CPU `raycastTileMap` sweep
      for that light entirely rather than adding GPU work on top of it.
      **What actually happened, in order** (kept for whoever picks this
      back up, so the false leads aren't retraced): (1) verified
      correct with a single light, in this session's own web/CanvasKit
      browser tool; (2) wiring it into every `test_game` light produced
      an oversaturated white blob and a separate hard-edged white
      rectangle — investigated, found a genuine `main.dart.js`
      MIME-type error proving the dev server was intermittently serving
      stale JS at that point, concluded (wrongly, as it turned out) that
      the bug was purely that stale-reload artifact, since a byte-for-
      byte identical config then rendered correctly on a freshly
      restarted dev server across both levels; (3) shipped/committed
      `test_game` wired up with `useGpuShadows: true` everywhere on
      that basis; (4) installed a real **release APK** (no dev server
      involved at all) on the same physical Android device the original
      fps report came from, and the identical oversaturated white-blob
      bug reproduced immediately and reliably — conclusively ruling out
      "just a stale dev server" as the explanation. The dev-server
      artifact from step (2) was real, but was a red herring masking a
      *second*, still-unidentified, genuinely device/release-build-
      reproducible bug. Reverted `test_game`'s lights to
      `useGpuShadows: false` (plain CPU path) immediately and confirmed
      via a fresh release-APK install that this restores the correct,
      working render on-device. **Root cause not yet found** — no
      working hypothesis survived the device reproduction (ruled out:
      cone lights specifically, light count specifically, degenerate/
      NaN uniform values via added defensive guards that didn't fix
      it). `Light2D.useGpuShadows` stays in the engine, default `false`
      (so nothing depending on this engine is at any risk), with this
      history preserved on the field's own doc comment as an explicit
      warning not to rely on it yet. Full `engine_flutter` suite and
      `--fatal-infos` analyze clean (the shader-dependent pixel test
      skips gracefully in this sandbox — `flutter test` can't compile/
      bundle a `shaders:` asset here, confirmed via `flutter pub get`
      itself failing on this sandbox's known pub.dev network
      restriction). **Before touching this again**: get a proper GPU/
      Skia frame-capture from the real device (this environment has no
      such tooling) rather than guessing further from screenshots — the
      bug is real and reproducible on-device, just not yet isolated to
      a specific cause. The single-multi-light-shader-pass idea (one
      draw call for every light via uniform arrays, instead of one
      per light) is still worth doing eventually for both performance
      and potentially fixing this by construction, but shouldn't be
      started until the current single-light-per-pass version's bug is
      actually understood — building a bigger version of code with an
      unexplained defect on top of that same defect is how bugs
      multiply, not how they get fixed.

