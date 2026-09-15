# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

Everything completed through the v1.0-release-readiness pass and the
"New engine features (round 2)" streak (including its full "Rendering"
group) has been cleared from this file — see [CHANGELOG.md](CHANGELOG.md)
for what shipped and git history for the full why behind each change.

## Documentation

- [x] `engine_flutter`'s `README.md` was missing `Light2D`/
      `EngineView.ambientBrightness`, `NineSliceSprite`,
      `AnimationTransition`/crossfading, `EngineView.fixedTimestepSeconds`,
      and its "mask/clip" note was stale (pointed at this same TODO
      file for a feature that, by the time of this pass, already
      shipped as `ClipShape`). Added: a full "Lighting (`Light2D`)"
      section (`ambientBrightness`, `castsShadows`/`blockOneWayPlatforms`,
      `coneAngle`/`coneDirection`, `colorArgb` tint vs. the newer
      `overbrightIntensity` additive-stacking glow, `flickerSpeed`/
      `flickerAmount`, `minZIndex`/`maxZIndex`, `openAirFalloffScale`,
      and the cosmetic/perf knobs `shadowEdgeSoftness`/
      `shadowSmoothingSeconds`/`cacheShadowGeometry`); a "Masking/
      clipping (`ClipShape`)" section replacing the stale note;
      crossfading + `NineSliceSprite` added to "Components/systems this
      package adds"; a new "Fixed timestep" section; `maxFps` added to
      the `GameConfig` JSON example with its virtual-clock-scheduling
      explanation; `SaveGame`'s schema-versioning (`version`/`migrate`/
      `SaveVersionException`) added to "Save/load". `engine_core`'s
      README also brought up to date in the same pass (its own gap was
      real, not just "spot-checked lighter" — none of these existed):
      `entitiesWithAll`/`entitiesWithinRadius`/`hasLineOfSight` added
      to the `WorldView`/`Behavior` section, plus new "Pathfinding"
      (`findPath`, the `_MinHeap`-based A*) and "Localized strings
      (`StringTable`)" sections. `StringTable` lives only in
      `engine_core` (confirmed via `engine_core.dart`'s exports —
      `engine_flutter` never re-exports it), so it's documented there
      only, not duplicated into `engine_flutter`'s README.

## Tooling / release

- [x] `game_agent pack-assets` — explicit request: "add a pre build-run
      hook that combines all image assets of levels into one sprite
      pack, then refer to that with build flags in run/build time."
      New CLI command (`engine_cli`, pure Dart — the `image` package
      already a dependency for `lint --render`) recursively scans an
      input directory, greedily row-packs every PNG/JPEG/BMP/GIF it
      finds into one sheet, and writes a manifest in exactly the
      `{"regions": {"name": {"x","y","w","h"}}}` shape
      `SpriteAtlas.fromManifest` (`engine_flutter`) already reads for a
      hand-authored atlas — no new parsing code needed on the consuming
      side, only a place to point it at. Deterministic sort order (by
      file path) so the same input directory always packs into the same
      sheet, not something that churns on every run purely from
      filesystem iteration order. `--padding` (default `2`) leaves
      transparent gaps between regions to avoid texture-filtering bleed;
      two source images resolving to the same region name (basename
      without extension) is a hard error, not a silent overwrite.
      Consumed at run/build time via three new opt-in `GameConfig`
      fields (`packedAtlasId`/`packedAtlasImage`/`packedAtlasManifest`,
      all `null` by default — zero behavior change for an existing
      game): `GameRunner` auto-registers the packed atlas into every
      loaded `Scene`'s `AtlasRegistry` under that id (skipped if a scene
      already registered something there itself — a scene's own
      `loadAssets` always wins), decoding it once and reusing that same
      `SpriteAtlas` across every scene switch rather than re-decoding
      per load. Gated by a new `usePackedAtlas` compile-time flag
      (`bool.fromEnvironment('USE_PACKED_ATLAS', defaultValue: true)`)
      — the actual "build flag" the request asked for: run
      `flutter run --dart-define=USE_PACKED_ATLAS=false` to fall back
      to per-scene individual atlas loading while iterating on art,
      without re-running the packer or touching `game_config.json`.
      Verified: 6 new `pack_assets_command_test.dart` tests (missing/
      nonexistent/empty `--input`; real packing with nested
      subdirectories, non-overlapping regions verified by sampling
      actual composited pixel colors, not just checking the manifest
      shape; `--padding` keeps adjacent regions apart; default manifest
      path derivation; duplicate-name collision is an error) and 3 new
      `packed_atlas_test.dart` `GameRunner` widget tests (unset config
      never touches the asset bundle at all; set-but-unmocked never
      resolves to a rendered `EngineView`, proving the load is actually
      attempted; a scene's own atlas under the same id wins, which
      — since no asset mock is installed for that test at all — also
      proves the auto-registration is skipped entirely rather than
      attempted and clobbering the result). Full `engine_cli` (21
      tests) and `engine_flutter` suites green, `--fatal-infos` analyze
      clean on both. **Known limitation, not attempted here**: the row
      packer is a simple greedy shelf packer, not a true bin-packer
      (e.g. MaxRects) — good enough since the sheet is a regenerated
      build artifact, not hand-tuned/committed art, but leaves real
      texture-memory savings on the table for an atlas with very
      differently-sized sprites; a genuine MaxRects implementation is a
      candidate follow-up if a real game's packed sheet turns out
      meaningfully oversized.
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

- [x] True bin-packing for `pack-assets` — replaced the shelf packer
      with a real MaxRects bin-packer (Best Short-Side-Fit heuristic):
      tracks actual leftover free rectangles and splits/prunes them as
      items place, instead of sizing every row by its tallest item (a
      real, measurable waste for a mixed-aspect-ratio set — a shelf
      packer forced a narrow item next to a tall one to "pay for" the
      tall one's full height). Grows the bin (both dimensions ×1.25,
      capped at 20 attempts) and retries from scratch whenever an item
      doesn't fit at the current size, seeded from `sqrt(totalArea)` so
      most real inputs pack on the first or second attempt; `--max-width`
      keeps its meaning as a starting size hint, no longer a hard row-wrap
      cap. Verified: existing region-correctness/padding/duplicate-name
      tests all still pass unmodified against the new packer, plus 2 new
      tests — a mixed tall-narrow-plus-many-small-items set stays within
      2× the theoretical minimum area (a shelf packer would blow well
      past this for exactly this shape of input), and a single item wider
      than `--max-width` still packs correctly (proving the bin actually
      grows rather than treating the flag as a cap). `engine_cli`'s full
      suite green, analyze clean.
- [x] `pack-assets --mipmaps`/multiple output resolutions — new
      `--scales` flag (default `"1.0"`, unchanged single-tier behavior)
      packs one additional resized sheet+manifest pair per requested
      tier, e.g. `--scales 1.0,0.5,0.25`. Resolved the open design
      question ("how does a `Sprite`/`TileMap` pick which tier to load")
      the same way Flutter's own asset-variant system already resolves
      it for plain assets: an `@<scale>x` filename suffix convention
      (`atlas.png` -> `atlas@0.5x.png`), with *picking* a tier at
      runtime left to the consuming game (screen density, an explicit
      config) rather than decided inside the engine — this command only
      produces the tiers. The `1.0` tier always keeps the plain
      `--output-image`/`--output-manifest` paths unsuffixed, so an
      existing single-tier caller's output doesn't change at all.
      Verified: 4 new tests (one sheet+manifest pair per tier with
      correctly scaled region dimensions in each; a tiny source image
      clamped to at least 1px per side rather than rounding to a
      degenerate 0×0 region at a small scale; `--scales` rejects a
      non-numeric or non-positive value). `engine_cli`'s full suite
      green, analyze clean.
- [x] Batch `_drawTileMapDebug`/`_drawColliderDebug` (`engine_flutter`)
      the same way `_collectSpriteItems` already batches regular sprite
      rendering via `Canvas.drawAtlas` — every collider circle now
      shares one `Path` (`addOval` per collider) stroked in a single
      `drawPath` call instead of one `drawCircle` per collider (they all
      already shared the same `Paint`, so batching costs nothing in
      fidelity); every tile border groups into one of 3 `Path`s by
      collision kind (solid/one-way/slope), each stroked once, instead of
      one `drawRect` per tile — an empty kind (e.g. a level with no slope
      tiles) is skipped entirely rather than issuing a no-op `drawPath`
      call. Verified: existing `collider_debug_test.dart` suite (render-
      without-crashing coverage for both paths) passes unmodified against
      the batched implementation; full `engine_flutter` suite (238 tests)
      green, analyze clean.
- [x] Cache `_lightClipPath`'s (engine_view.dart) visibility-polygon
      per shadow-casting light — new opt-in `Light2D.cacheShadowGeometry`
      (`false` default, zero behavior/cost change unless set) reuses the
      previous frame's per-ray *world-space* hit distances instead of
      re-running the `raycastTileMap` sweep, whenever every input that
      could change them (world `Position`, `radius`, `coneAngle`,
      `coneDirection`, `shadowRayCount`, `blockOneWayPlatforms`,
      `castsShadows`) is bit-for-bit identical to last frame's — a
      static shadow-casting light (a torch on a wall) now skips the
      sweep entirely once its geometry has been computed once. The
      screen-space `Path` itself is still rebuilt fresh every frame from
      those distances regardless of cache hit/miss, so a cached light's
      shadow still correctly follows `Camera` panning/zooming. Explicitly
      does **not** detect the level's own `TileMap` content changing
      out from under a stationary light (no mutation-versioning exists
      for `TileMap` yet) — documented as a caveat on the field, not
      silently wrong: a game with destructible/changing geometry near a
      cached light must not enable this, or must force-invalidate itself
      (nudge any keyed field) exactly when the geometry changes. Avoided
      exactly the `shadowSmoothingSeconds` mistake (interpolating toward
      a new value, which read as the shadow visibly lagging) — a cache
      hit is pixel-identical to the equivalent uncached frame, a cache
      miss invalidates completely and immediately, never a blend.
      Verified: 4 new tests — off by default (`cachedShadowDistances`
      stays `null`, zero side effect unless opted in); on, a static
      light reuses the *exact same* `List<double>` instance across
      multiple frames (proven via `identical()`, not just equal values
      — confirms the raycast sweep genuinely didn't re-run); on, moving
      the light invalidates the very next frame (no one-frame-late
      lag); on, changing `radius` also invalidates (not position-only).
      Full `engine_flutter` suite (242 tests) green, analyze clean.
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
- [x] `World.step`'s system loop, profiled: `world_step_benchmark.dart`
      (movement-only, the cheapest possible system) shows clean linear
      scaling with entity count (100 -> 1000 -> 5000 entities: ~7.6us ->
      ~76us -> ~358us per step) and no evidence of cache-unfriendliness
      or quadratic blowup from the dense-array-per-`ComponentStore`
      iteration pattern — even at 5000 entities this is ~2% of a 60fps
      frame budget. `TileCollisionSystem` and (pre-fix) `CollisionSystem`
      were read specifically looking for avoidable per-tick allocation;
      `TileCollisionSystem` has none, but `CollisionSystem` did have a
      real one (see its own `[x]` entry immediately below) — found by
      exactly this profiling pass, not purely speculative after all.
      `TileCollisionSystem`/general system-loop iteration itself: no
      confirmed bottleneck at realistic entity counts, closed as
      measured rather than left an open guess.
- [x] `CollisionSystem` was rebuilding a brand-new `SpatialHash` (a new
      `Map` plus a fresh bucket `List` allocated for every occupied
      cell) from scratch on *every single tick* — found via exactly the
      profiling pass the item above called for, not a guess. Fixed by
      reusing one `SpatialHash` instance across ticks (rebuilt only
      when auto-sizing's `cellSize` or `world.width` actually changes —
      a `SpatialHash`'s cell-hashing math is fixed at construction, so
      reusing it across a real `cellSize` change would silently
      misplace entities), with `SpatialHash.clear()` now recycling each
      touched cell's bucket `List` into a pool instead of either
      discarding it (allocates fresh again next tick) or leaving it
      sitting in the map forever (a real regression an earlier version
      of this fix actually introduced — see below). **A genuine mistake
      caught by this engine's own benchmark, not just written and
      assumed correct**: the first attempt just emptied every bucket
      in place without ever removing map entries, which kept every
      cell any entity had *ever* visited resident forever — harmless
      at first, but `forEachNearbyPair` iterates every entry in that
      map every tick, so a session with entities that keep moving
      (any real game) would have that iteration cost grow *with total
      play time*, not with current entity count. `collision_system_
      benchmark.dart` caught this immediately as a 3-4x regression at
      n=100 despite passing every correctness test (the benchmark's
      own entities drift slightly each tick via `MovementSystem`,
      accumulating touched cells over its many warmup iterations).
      Fixed properly with an explicit `_activeKeys` list (only cells
      touched *this* cycle) plus a bucket-`List` pool, bounded by the
      largest number of simultaneously-active cells ever seen in one
      cycle, not by total cells ever touched across the instance's
      lifetime. Verified: 2 new regression tests in
      `collision_system_test.dart` (a reused hash doesn't leak a stale
      pair once entities move apart; a reused hash correctly rebuilds,
      not silently keeps stale cell-hashing math, when auto-sizing's
      cellSize legitimately changes between ticks) and 1 new
      `spatial_hash_test.dart` test (repeated clear()+insert() cycles
      into the same cells with different entity ids each time, proving
      no cross-cycle leakage). Benchmarked before/after
      (`collision_system_benchmark.dart`, 3 runs each): n=100 ~196us ->
      ~174us, n=1000 ~1789us -> ~1730-1760us, n=5000 ~535ms -> ~475ms
      (the n=5000 case is still dominated by that benchmark's
      deliberately-packed O(n²)-per-cell density, unrelated to this
      fix, per the class's own existing doc comment — the allocation
      savings alone still shaved off real, measured time even there).
      `engine_core` full suite (179 tests) and `engine_platformer` full
      suite green, `--fatal-infos` analyze clean on both.
- [x] `AtlasRegistry`/`SpriteAtlas` didn't support unloading at all —
      new `AtlasRegistry.unregister(String id)` removes the entry and
      calls `ui.Image.dispose()` on its decoded image, actually
      releasing the GPU texture instead of just dropping the registry's
      own reference to it (which alone doesn't guarantee prompt release).
      Deliberately just the *mechanism*, not a policy: this repo's own
      "needs an explicit lifecycle decision (unload on `loadScene`?
      reference-count across scenes sharing one atlas id?)" question is
      still open and belongs to a specific game's scene-switching design,
      not something the engine should decide unilaterally — a game calls
      `unregister` itself once it knows an atlas is genuinely done with
      (e.g. from its own room-exit logic). Doesn't reference-count: if
      the same `SpriteAtlas` instance is deliberately registered under
      two ids, unregistering one disposes the shared image out from under
      the other too — documented on the method, not silently handled,
      since guessing at sharing semantics here would be worse than
      requiring the caller to know its own atlas graph. Verified: 2 new
      tests (`unregister` actually disposes the image — confirmed by a
      post-dispose call that needs the native handle throwing, not just
      a getter that reads a cached field; unregistering a never-
      registered id is a harmless no-op returning `false`). Full
      `engine_flutter` suite (238 tests) green, analyze clean.
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
- [x] Audio: `AudioManager` didn't pool/reuse player instances for a
      rapidly-repeated short sound effect — `playSound` now reuses a
      pooled, idle `AudioPlayer` (LIFO — most recently used first, up
      to `_maxPoolSize` (`8`) idle players kept at once) instead of
      constructing a fresh one per call and disposing it on completion;
      constructing an `AudioPlayer` sets up real platform-channel/native
      player state on every platform `audioplayers` supports, genuine
      avoidable overhead at the trigger rates this item's own example
      (several pickups within one second) implies. A burst past the
      pool cap still gets its own short-lived player (disposed on
      completion, not pooled), so overlapping SFX beyond `_maxPoolSize`
      concurrent ones still all play correctly. Verified: existing
      construct/disposal-only test coverage still passes; a deeper test
      actually exercising `playSound`'s pooling path (a player
      completing, returning to the pool, and being reused) was tried
      and reverted — `play()` routes all the way through
      `audioplayers`' `AudioCache` to a real asset-bundle load before
      this package's existing platform-channel mock (no asset/event-
      channel simulation) is ever reached, throwing "Unable to load
      asset" for any path not in the test bundle — the exact same
      rabbit hole `audio_manager_test.dart`'s own top comment already
      flags for every other `AudioManager` method; not worth chasing
      further in a unit test than this file's established construction/
      disposal-only precedent. `engine_flutter` analyze clean.
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

## Features (engine_flutter)

- [x] Full cinematic camera + screen-effect support — explicit request
      ("full cinematic support, panning, following, zooming, shaking,
      changing colors, adding effects"). `CinematicSystem`/
      `CinematicStep` already existed (`engine_core`) as a pure
      sequencing engine with no opinion on what a step actually does;
      only the step *implementations* were missing. New
      `CameraPanStep`/`CameraZoomStep`/`CameraShakeStep`/
      `CameraFollowStep` + `ScreenTint` component + `ScreenTintStep`,
      all in `engine_flutter` (not `engine_core`, alongside
      `CinematicStep`) since `Camera` is a rendering-only concept with
      no ECS/`World` presence — a step needs the actual `Camera`
      instance `EngineView` renders with, not something look-up-able
      from `World`. Pan/zoom capture their *from* value at `start()` so
      steps chain without hand-tracking the previous step's endpoint;
      `CameraFollowStep` continuously re-centers on a moving target for
      one beat, distinct from `Scene.cameraFollowEntity`'s whole-scene
      hard-snap following (a `Scene` using any of these steps must
      leave `cameraFollowEntity` unset, or `EngineView`'s per-tick hard
      snap undoes the step's own work that same tick).
      Two real bugs found only by live browser testing, neither caught
      by the otherwise-comprehensive unit suite (now both covered by
      regression tests): (1) a `Scene` referencing its own `late
      Camera` field inside `populate()` threw `LateError` — `Scene`'s
      documented lifecycle runs `populate()` before `createCamera()`,
      so a field assigned inside the latter doesn't exist yet when the
      former needs it (surfaced only as an uncaught console promise
      rejection + an infinite loading spinner, no visible error
      overlay) — general fix: initialize such a field at declaration
      instead. (2) chaining two independent `ScreenTintStep`s as a
      flash (up then down) left the "up" step's entity stuck at its
      peak alpha forever, since each spawned its own `ScreenTint`
      entity by default and nothing ever animated the first one back
      down — fixed with a mutable, shareable `entity` constructor
      parameter. Verified: 15 new tests in
      `cinematic_camera_steps_test.dart` (pan/zoom/shake/follow
      behavior and skip; `ScreenTint` round-trip; both the
      unshared-entity bug and the shared-entity fix as explicit
      regression tests) and 3 new widget tests in
      `screen_tint_rendering_test.dart`. `test_game`'s new (gitignored)
      `CinematicDemoScene` exercises the whole set end-to-end —
      reachable via a new "CINEMATIC DEMO" button on the main menu —
      and was used to find both bugs above live before they were fixed.

- [x] Real masking/clipping: new `ClipShape` component
      (`engine_flutter`, circle or rect centered on `Position`) with a
      `ClipShapeMode`: `reveal` (only show the scene where at least one
      reveal shape covers it — spotlight/peephole/wipe transition) or
      `cutout` (punch a hole through the already-drawn scene — a
      vignette). The two modes need genuinely different `Canvas`
      mechanisms, not two branches of the same one: `Canvas` is
      immediate-mode, so `reveal` has to clip drawing *as it happens*
      (the whole draw body wrapped in `canvas.save()`/`clipPath`/
      `restore()`), while `cutout` has to erase pixels *already*
      drawn, which only works inside a layer you still control —
      wrapped the draw body in `canvas.saveLayer()`, then after the
      reveal-clip is restored, each cutout shape is stamped with
      `BlendMode.dstOut` (blurred via `MaskFilter.blur` when
      `softness` > 0) before the final `restore()` composites the
      layer back. Both paths are skipped entirely (zero cost, not even
      a `save()`) when no `ClipShape` of that mode exists in the
      world. Verified: `clip_shape_test.dart` — `toJson`/`fromJson`
      round-trip plus the unknown-mode-string fallback; two real
      pixel-sampling widget tests (same `RenderRepaintBoundary.toImage`
      technique as the z-banded-lighting test) proving `reveal`
      actually clips a sprite outside the shape to fully transparent
      while a sprite inside it still draws, and proving `cutout`
      actually erases a sprite under the shape to fully transparent
      while a sprite elsewhere is untouched — not just "renders
      without crashing"; plus coexistence, rect-shape, no-`Position`,
      and no-`ClipShape`-present crash-safety tests. Full
      `engine_flutter` suite and `flutter analyze --fatal-infos` clean.

- [x] Textured `TileMap` rendering: new `TileMap.atlasId` (`null`
      default) + `TileMap.regionByTileId` (empty default — a tile id
      with no entry still falls back to the flat debug color even when
      `atlasId` is set, so a level can texture some ids and leave
      others, e.g. an invisible trigger marker, as plain color).
      `EngineView._collectTileMapItems` resolves the atlas once per
      `TileMap` (not per tile) and, for each tile id with a real,
      loaded region, `canvas.drawImageRect`s it instead of the flat
      color — the exact same region-in-an-atlas mechanism `Sprite`
      already uses, just applied per grid cell. Kept as plain
      `String`/`Map<int, String>` fields on `TileMap` (`engine_core`,
      no Flutter dependency) rather than anything Flutter-typed, same
      pattern `Sprite.atlasId`/`.region` already establish in
      `engine_flutter`; `TileMap` already carried one rendering hint
      (`zIndex`) so this isn't a new kind of leak. Verified: 2 new
      `engine_core` tests (round-trip, and `atlasId` omitted from
      `toJson` entirely — not serialized as `null` — when unset) and 3
      new `engine_flutter` widget tests (a tile with a real loaded
      region draws without error; a tile id with no `regionByTileId`
      entry falls back to flat color even when `atlasId` is set and
      loaded; an `atlasId` that isn't registered yet in the
      `AtlasRegistry` falls back cleanly, not a crash). Full
      `engine_core` (176), `engine_flutter` (198), and
      `engine_platformer` (176) suites green, `--fatal-infos` analyze
      clean on all three. Live in `test_game`: `main.level.json`'s
      ground/platform tiles (`solidTileIds: {1}`) now reference the
      `tileset` atlas's existing `dirt_top_mid` region (an atlas the
      game already loaded but never used for anything) — the level
      visibly renders real dirt texture instead of flat gray blocks,
      while the ladder/icy/conveyor tiles keep their distinct
      translucent colors (no `regionByTileId` entry for those ids).

## New engine features (round 2) — Core (`engine_core`)

- [x] Multi-layer / animated tiles: new `TileMap.backgroundTiles`/
      `foregroundTiles` (both `null` by default — a single-layer level,
      still the common case, pays nothing extra) are purely visual
      layers, same `cols*rows` shape as `tiles`, drawn under/over the
      main layer respectively; collision only ever comes from
      `tiles`/`solidTileIds`/etc., never these. New
      `TileMap.tileAnimations` (`Map<int, List<int>>`, base id -> cycle
      of tile ids) + `tileAnimationFps` (default 6) + a new
      `TileAnimationSystem` (`engine_core`, opt-in the same way
      `TweenSystem` is — not auto-added) that advances
      `TileMap.animationElapsed` each tick; `TileMap.currentTileId`
      resolves a base id to its current frame's id from that elapsed
      time, wrapping back to frame 0 past the end.
      `animationElapsed` is excluded from `toJson` (internal render/
      sim state, same pattern as `Light2D`'s shadow-geometry cache
      fields) so it never round-trips through a save file or a level
      JSON edit. Collision/solidity always keys off the *base* tile id
      regardless of which animated frame is currently showing — a lava
      tile mid-animation still blocks/hurts based on its authored id.
      `EngineView._collectTileMapItems` draws background tiles first,
      then the main layer, then foreground tiles, all through one
      shared per-tile draw helper (texture-or-flat-color resolution,
      now also passing every tile id through `currentTileId` first) so
      the three passes don't triplicate that logic; background/
      foreground tiles never contribute a collision-kind flat color
      (one-way blue, slope orange, etc.) since those layers carry no
      collision meaning. Verified: 12 new `engine_core` tests in
      `tile_map_test.dart` (background/foreground null-by-default,
      wrong-length rejected, independent-grid reads, JSON round-trip/
      omission; `currentTileId` no-animation passthrough, frame
      cycling/wrapping at a given `tileAnimationFps`, JSON round-trip/
      omission, `animationElapsed` excluded from `toJson`) plus a
      `TileAnimationSystem` test (`animationElapsed` advances by `dt`
      across ticks). 3 new `engine_flutter` widget tests in
      `tile_rendering_test.dart`: a background-layer-only cell still
      draws (proves the background pass actually runs), a cell with
      both a main and foreground tile renders without crashing, and a
      genuinely end-to-end animation test (`TileAnimationSystem` wired
      into a real `World`, ticked via `tester.pump`, asserting
      `currentTileId` actually flips from frame 0 to frame 1 once
      enough simulated time has elapsed — not just that the data model
      alone can compute a frame index). Full `engine_core`,
      `engine_flutter`, and `engine_platformer` suites and
      `--fatal-infos` analyze all clean.
- [x] Deterministic RNG + replay/record: new `DeterministicRandom`
      (`engine_core`) wraps a seeded `dart:math Random`, with `reset()`
      replaying the identical sequence from the start (needed to
      re-run a recorded replay deterministically) without callers
      having to re-construct/re-share a new instance. New
      `ReplayRecorder`/`ReplayPlayer` capture and play back a
      timestamped sequence of arbitrary JSON snapshots — deliberately
      generic (not tied to `InputState`, which lives in
      `engine_flutter` and would be a backward dependency), so the
      same mechanism replays recorded input, recorded agent actions,
      or any other per-tick data a game wants to capture.
      `ReplayPlayer.step` delivers every frame whose recorded `dt` has
      elapsed within that step — a single large/stalled `dt` can
      deliver multiple frames in one call, matching what a live run
      under the same stall would have produced, rather than only ever
      firing one frame per `step` call. Verified: 5 new
      `deterministic_random_test.dart` tests (same-seed reproduces,
      different seeds diverge, `reset()` replays identically,
      `nextRange` bounds, `seed` readback) and 8 new
      `replay_recorder_test.dart` tests (recording order/dt,
      `clear()`, JSON round-trip, timed delivery, multi-frame delivery
      in one stalled step, `reset()` rewinds, empty-recording
      `isFinished`). Full `engine_core` suite and `dart analyze
      --fatal-infos` both clean.
- [x] Content hot-reload: new `LevelHandle` (`engine_core`) wraps
      `Level.loadInto`/`reload` for a *running* `World` —
      `LevelHandle.load` tracks every entity id a level spawned (named
      and unnamed alike; `Level.loadInto`'s own return value is
      deliberately only the named subset, so this needed its own
      tracking rather than reusing that), and `reload(newJson)`
      destroys exactly those tracked entities before spawning the new
      set — entities that existed in the `World` before the level was
      ever loaded (or that belong to a different `LevelHandle`) are
      left untouched. `reload` validates the new JSON *before*
      destroying anything, so a malformed edit — the common case while
      iterating on content — throws and leaves the previous, working
      level fully intact rather than tearing it down for a load that
      was never going to succeed. Verified: 5 new
      `level_handle_test.dart` tests (tracks named + unnamed ids on
      load; reload tears down only its own tracked entities, not
      pre-existing or other-handle ones; stale names drop out after a
      reload; a malformed reload throws `LevelLoadException` and
      leaves the prior level's entity count/ids/aliveness untouched).
      Full `engine_core` suite and `dart analyze --fatal-infos` clean.

## Lighting follow-ups

Real gaps identified while building and then actually using basic 2D
lighting (`Light2D`/`EngineView.ambientBrightness`) in `test_game` —
all five closed out in one pass.

- [x] Per-scene ambient brightness: new `Scene.ambientBrightness`
      (`null` default — "use `GameConfig`'s global setting," unchanged
      behavior) that `Game` prefers over the global config value when
      set (`loaded.scene.ambientBrightness ?? widget.game.config.ambientBrightness`).
      `ButtonMenuScene` (the base every menu in this engine builds on,
      not just one specific menu) overrides it to `1.0` — a menu isn't
      a lit game world and shouldn't darken just because gameplay uses
      lighting. Verified live in the browser: `test_game`'s main menu
      no longer darkens (confirmed both before this fix, darkened, and
      after, not).
- [x] Colored lights: `Light2D.colorArgb` (default `0x00FFFFFF` —
      *transparent* white, meaning "no tint pass at all," not opaque
      white, so the default costs nothing extra and changes nothing
      visually). The color's own alpha channel doubles as tint
      strength — an opaque-ish color like `0xAAFF6600` tints visibly,
      alpha `0` skips the whole additive pass. Implemented as a
      separate additive (`BlendMode.plus`) radial-gradient pass drawn
      *after* the darkness mask is composited back onto the real scene
      (additive blending needs the scene's actual colors underneath it,
      which only exist post-composite) — the brightness-reveal pass
      alone (via `BlendMode.dstOut`, erasing only alpha) can't add
      color, only reveal what's already there.
- [x] Shadow casting: new `Light2D.castsShadows` (`false` default,
      unchanged plain-circle behavior). When on, `EngineView` samples
      48 rays around the light via `raycastTileMap` (the exact same
      primitive `WorldView.hasLineOfSight`/AI already use) to build a
      visibility-polygon `Path`, clipping the reveal (and, if present,
      the color-tint) to it — real occlusion by `TileMap` walls, not a
      full shadow-volume renderer (a meaningfully bigger scope), but a
      legitimate, well-known 2D-shadow-casting technique. Verified two
      ways: (1) exact numeric assertions in `light2d_test.dart`'s new
      "Shadow casting occlusion math" group — a solid tile stops a
      raycast well short of the light's radius at the precise expected
      distance, an unobstructed direction reaches the full radius
      unblocked, both directly against `raycastTileMap` (the same
      primitive the render path calls), not just "doesn't crash"; (2)
      live in the browser against `test_game`'s **real level
      TileMap/textures** — the player's light, both torches, and a new
      flashlight-style cone light all have `castsShadows: true` active
      simultaneously against the actual level geometry and sprites,
      confirmed rendering with no crashes and no console errors.
- [x] Animated/flickering lights: `Light2D` gained `flickerSpeed` (`0`
      default — disabled) + `flickerAmount`, `baseIntensity`/
      `baseRadius` (defaulted from the constructor's `intensity`/
      `radius` args so enabling flicker on an existing light needs no
      extra setup), and `flickerElapsed` (runtime). New
      `LightFlickerSystem` oscillates `intensity`/`radius` around the
      base values using two layered sine waves (deliberately not real
      randomness — smoother frame-to-frame, and keeps `Light2D` plain
      seedless data rather than needing a stored, JSON-round-trip-safe
      `Random` seed per light) — a no-op, near-zero-cost for any light
      with `flickerSpeed == 0`. Verified: `LightFlickerSystem` tests
      confirm disabled-by-default is a true no-op, oscillation stays
      correctly bounded, and intensity clamps to `[0, 1]` even under a
      deliberately extreme `flickerAmount`. Live in the browser:
      `test_game`'s two torches flicker (`flickerSpeed: 3,
      flickerAmount: 0.15`) with no crashes.
- [x] Directional/cone lights: `Light2D.coneAngle` (`null` default —
      full 360° point light, unchanged) + `coneDirection`. When set,
      the same visibility-polygon machinery shadow casting uses builds
      a pie-slice fan instead of a full circle (sampling only across
      the cone's angular width) — cones and shadow casting compose for
      free, since both go through the identical clip-path code path.
      Verified: dedicated cone and shadow-casting-cone widget tests
      render without crashing; live in the browser, `test_game`'s new
      flashlight-style cone light (`coneAngle: 0.9`, also
      shadow-casting) renders correctly against the real level.

All five verified together, live, in one pass: `test_game`'s player
light, two colored/flickering torches, and the new cone light are all
active simultaneously against the level's real `TileMap`/sprite
textures, with `showColliderDebug`/the FPS overlay/coin HUD text all
still rendering correctly on top. Full `engine_flutter` suite green
(15 new tests in `light2d_test.dart`, bringing it to 22, plus 1 new in
`button_menu_scene_test.dart`), `dart analyze --fatal-infos` clean.

## Lighting follow-ups (round 2)

Two more gaps, spotted after actually running several shadow-casting
lights together in `test_game`: every `Light2D` in the world was
processed every frame regardless of whether it was anywhere near the
camera, and shadow raycasting always sampled a hardcoded 48 rays no
matter how small or large the light. Both closed out in one pass.

- [x] Viewport culling: `EngineView._drawLighting` now skips a light
      entirely — including its shadow-casting raycasts, the expensive
      part — when its screen-space circle doesn't intersect the
      current viewport rect (`_circleIntersectsRect`, a closest-point-
      on-rect distance check). Purely an internal cost cut, no API
      change and no visible behavior change for anything on screen;
      matches the same reasoning as `_collectTileMapItems`'s earlier
      tile culling. Verified: a dedicated widget test places a
      shadow-casting light thousands of pixels outside a 400×300
      viewport and confirms it still renders without crashing (proving
      the cull path itself, not just "renders," since a bug in the
      cull math throwing or producing a degenerate rect would show up
      here); the existing on-screen shadow-casting tests continue to
      pass unchanged, confirming lights actually on screen are
      unaffected.
- [x] Configurable shadow ray count: new `Light2D.shadowRayCount`
      (`48` default — the feature's original fixed value, unchanged
      behavior for any light that doesn't set it), read by
      `EngineView._lightClipPath` instead of the hardcoded constant,
      clamped to a minimum of `3` (fewer rays can't describe a closed
      polygon). Lets a level with many small shadow-casting lights on
      screen at once cut the per-light raycast cost, or one big
      dramatic light raise it past 48 to smooth out visibly faceted
      polygon edges — a real tuning knob discovered from having four
      shadow-casting lights active simultaneously in `test_game`.
      Verified: round-trip test in `light2d_test.dart`, plus widget
      tests for a custom count and for a count below the `3` floor
      (confirms the clamp, not just "doesn't crash on a weird input").
      Live in `test_game`: the player's light now sets
      `shadowRayCount: 64` (its widest, most prominent shadow, where
      the extra smoothness is actually visible) as a real usage
      example.

Full `engine_flutter` suite green (194 tests, 5 new in
`light2d_test.dart`), `dart analyze --fatal-infos` clean.

## Lighting follow-ups (round 3)

Reported live: a shadow-casting light's shadow visibly *flickers*
(edges popping/jittering frame to frame) while its light source is
moving, instead of the shadow sliding smoothly the way the light
itself does — fixed (see below). Also reported: lighting quality in
general "not very good" — two visual-quality items closed out
alongside the flicker fix and `blockOneWayPlatforms`, described below.
Remaining open items (entity shadow casting, additive overlap,
fixed-timestep interpolation) still need a design pass before
implementing.

- [x] Shadow-edge jitter from grid-raycast tie-breaking:
      `raycastTileMap`'s DDA traversal now steps *both* grid axes
      together whenever `tMaxX`/`tMaxY` are within a small epsilon
      (`1e-6`) of each other, instead of picking one via a strict `<`
      comparison. A ray passing near a tile-grid corner (common —
      `_lightClipPath` samples rays all the way around a light, so
      *some* ray is always near-diagonal relative to the axis-aligned
      grid) used to have `tMaxX`/`tMaxY` nearly tied, and which one a
      continuously moving light's position made momentarily smaller
      could flip from one frame to the next — sending the ray down a
      different sequence of tiles and changing whether a corner-
      adjacent solid tile blocked it, for a sub-pixel light move. That
      read as the shadow polygon's edge popping right where those
      near-diagonal rays landed. Stepping both axes together at a near-
      tie treats the ray as passing exactly through the shared corner
      (skipping straight to the diagonal tile, the same convention
      most grid-DDA-with-diagonal-handling implementations use) —
      deterministic regardless of which side of the tie a tiny origin
      perturbation falls on, so the flicker is gone at its actual
      source rather than papered over with smoothing. This is a real,
      if narrow, behavior change for the previously-undefined exact-
      corner case (a corner-adjacent solid tile that used to
      block a ray passing exactly through the corner no longer does,
      consistently) — `WorldView.hasLineOfSight`/pathfinding/AI all
      share this same primitive and their full test suites stayed
      green, so nothing else depends on the old tie-break's specific
      direction. Verified: new regression test in
      `engine_core`'s `raycast_test.dart` — five origins perturbed by
      sub-pixel amounts (`0`, `±1e-7`, `3e-8`, `-5e-8`) around an exact
      corner-tie all now produce the identical raycast result (all
      miss, consistently) where they'd previously have diverged
      (some hitting the corner-adjacent solid tile, some not) based on
      floating-point noise alone. Full `engine_core` (176),
      `engine_flutter` (198), and `engine_platformer` (176) suites
      green, `--fatal-infos` analyze clean on all three.
- [x] Shadow/light position isn't run through `EngineView`'s
      fixed-timestep interpolation: `_drawLighting` used to read a
      light's `Position` directly from the component store, while
      `Sprite`/`Particle` rendering goes through `_interpolated`
      (blends toward the current tick using `interpolationAlpha`)
      whenever `fixedTimestepSeconds` is set — a light attached to a
      moving entity would visibly lag/step relative to that entity's
      own smoothly-interpolated sprite instead of tracking it exactly.
      Fixed exactly as scoped: `_drawLighting` now runs each light's
      raw `Position` through the same `_interpolated` call
      sprite/particle rendering already uses before building its
      screen position/shadow raycasts/clip path — a pure no-op when
      `fixedTimestepSeconds` is unset (`_previousPositions` stays
      empty, so `_interpolated` always falls back to the raw
      `Position` outright), so every existing lighting test/behavior
      is unaffected. Verified: new widget test in `light2d_test.dart`
      (`'Light rendering under fixed-timestep interpolation'`) — a
      real pixel-sampling test (same `RenderRepaintBoundary.toImage`
      technique as the z-banded-lighting test), not just "doesn't
      crash": a light on a moving entity under `fixedTimestepSeconds:
      0.1`, sampled mid-accumulation (`interpolationAlpha` at `0.5`),
      renders its red tint centered on the *interpolated* world
      position (halfway between the previous and current fixed-step
      `Position`) rather than the raw, numerically-current-but-stale-
      relative-to-render-time `Position` — a pixel at the interpolated
      center is tinted, a pixel at the raw `Position` (50px away,
      outside the light's 30px radius) is untouched black. Full
      `engine_flutter` suite and `--fatal-infos` analyze clean.
- [x] One-way platforms never block light/shadows: new opt-in
      `Light2D.blockOneWayPlatforms` (`false` default, matching
      `raycastTileMap`'s own default and today's unchanged behavior)
      threaded straight into `_raycastLightDistance`'s `raycastTileMap`
      call. Verified: new test in `light2d_test.dart`'s "Shadow
      casting occlusion math" group asserts a one-way tile blocks a
      raycast when `blockOneWay: true` but not at the default, at the
      exact primitive `_raycastLightDistance` uses; a new widget test
      exercises a shadow-casting light with `blockOneWayPlatforms:
      true` against a real one-way `TileMap` tile end to end (renders
      without crashing). Live in `test_game`: the player's light now
      sets `blockOneWayPlatforms: true` (it's the one light actually
      near the level's one-way platforms) — loads and plays normally,
      steady 120fps, no console errors.
- [x] Only `TileMap` geometry casts shadows — implemented exactly as
      scoped: new `Collider.blocksLight` (`false` default, unchanged
      behavior — most colliders, a coin or an enemy's hurtbox,
      shouldn't cast a shadow just because they physically collide
      with something). `_raycastLightDistance` now also does a per-ray
      nearest-hit check against every `Collider(blocksLight: true)`
      entity (standard ray-vs-circle intersection —
      `_rayCircleDistance`, a new small helper), merged with the
      existing tile-hit distance via the same "take whichever is
      nearer" pattern multiple `TileMap`s already use there. The
      light's own entity is excluded from the check (a torch prop
      that's also solid would otherwise self-shadow at distance `0`)
      — threaded through as a new `lightEntity` parameter on both
      `_raycastLightDistance` and `_lightClipPath`. A ray whose origin
      already starts inside a blocking circle treats it as a miss, not
      an immediate zero-distance block — a light already overlapping
      something is never occluded by it. Verified: 2 new `engine_core`
      `collider_test.dart` tests (`blocksLight` default/round-trip)
      and 3 new `engine_flutter` widget tests in `light2d_test.dart`'s
      new "Collider(blocksLight: true) casts shadows" group — a tagged
      collider directly on a light's ray stops it right at the
      collider's near edge (reading `Light2D.cachedShadowDistances`
      directly, same technique the existing shadow-smoothing tests
      use); an *untagged* collider on the same ray leaves it fully
      unobstructed, proving the opt-in flag actually gates the check;
      a tagged collider entirely off the ray path doesn't affect it.
      Full `engine_core`/`engine_flutter`/`engine_platformer` suites
      and `--fatal-infos` analyze clean across all three.
- [x] Overlapping lights don't add brightness: the reveal pass (`BlendMode.dstOut`
      on the darkness mask's alpha) can only ever *erase*, so it floors
      at "fully revealed" and can't push a shared region brighter than
      one light alone already manages — not a one-line blend-mode swap,
      since dstOut has to stay exactly what it is for the darkness
      mask itself to work at all. Design chosen: a new, separate,
      opt-in `Light2D.overbrightIntensity` (`0` default, no extra draw
      cost when unset) — a third pass per light, plain white,
      `BlendMode.plus` against the *real scene colors* (same
      composited-after-the-mask ordering the color-tint pass already
      established, and reuses its exact clip/mask-filter plumbing via
      a new shared `_drawLightGradientCircle` helper — factored out
      once a third pass would otherwise have triplicated that
      save/clipPath/drawCircle/restore shape). Independent of
      `colorArgb`: a light can overbrighten without recoloring, or tint
      without overbrightening, or both. Because it's additive against
      real scene colors rather than an alpha-erase of a mask, two
      overlapping lights' glows genuinely stack — the exact effect
      asked for. Verified: 2 new widget tests in
      `light2d_test.dart` — with `overbrightIntensity` off (default),
      two exactly-overlapping lights read no brighter than one, proving
      the reveal pass alone really does cap there; with it set, two
      overlapping lights read strictly brighter than either light
      alone, a genuine before/after pixel comparison via
      `RenderRepaintBoundary.toImage`, not just "renders without
      crashing." Round-trip/default test included too. Full
      `engine_flutter` suite and `--fatal-infos` analyze clean.
- [x] A light reveals open air, not just surfaces — design chosen from
      the two candidates logged here: a secondary falloff by distance
      from the *nearest solid surface* was rejected as needing a real
      per-pixel SDF (a meaningfully bigger, riskier feature); "just use
      a smaller default radius" doesn't actually fix anything since a
      big level's open volumes still dwarf any reasonable default. Went
      with a targeted version of the surface-distance idea instead,
      scoped to what a shadow-casting light *already computes*: new
      `Light2D.openAirFalloffScale` (`1.0` default — every ray at its
      full raycast distance, unchanged behavior). Only meaningful with
      `castsShadows` on, since only then does `EngineView` have real
      per-ray hit data to tell "this ray struck a surface" from "this
      ray reached the full configured radius because nothing was
      there." A ray that hit something short of the radius is left
      exactly as raycast either way — a light still fully illuminates
      whatever surface it's actually next to; only a ray that traveled
      the *entire* radius unobstructed (genuinely open air) gets pulled
      in to `radius * openAirFalloffScale` instead. Threaded into
      `Light2D.cacheShadowGeometry`'s cache key too (a new
      `cachedShadowOpenAirFalloffScale` field) — missed, this would
      have let a stale, wrongly-scaled sweep survive a scale change.
      Verified: 2 new `light2d_test.dart` tests reading
      `cachedShadowDistances` directly (same technique the shadow-
      smoothing tests already use) — a ray toward a real solid tile
      keeps its raycast distance untouched by the scale, while a
      genuinely open ray in the same sweep is pulled in to the expected
      `radius * scale`; a separate test confirms the `1.0` default
      leaves every open ray at the full radius. Plus a new
      cache-invalidation regression test (changing
      `openAirFalloffScale` alone invalidates a cached sweep, mirroring
      the existing radius-change test). Full `engine_flutter` suite and
      `--fatal-infos` analyze clean.
- [x] Softer, more natural falloff + soft shadow edges: three attempts
      to get this right, in order — a flat 2-stop linear falloff
      (uniform dimming center-to-edge, read as artificial); a 3-stop
      curve that over-corrected into a large, uniformly-bright "glowing
      disc" (reported live as "cartoony"); a 6-stop quadratic `(1-t)²`
      curve that dimmed immediately from the peak — smoother than the
      first two, but still read as the *light itself* being soft/hazy
      rather than a real light with only a soft *edge* (reported live:
      "I want edges of light to be soft, not light itself"). Landed on
      a **plateau** shape instead of a curve at all: full strength held
      flat out to 60% of the radius (the light's body reads as a real,
      solidly-lit area, not hazy from its own center), falling off only
      over the remaining 40%, landing fully faded right at the edge —
      softness concentrated at the boundary, not smeared across the
      whole light. Both the reveal and tint passes build their gradient
      colors from one shared `_falloffColors`/`_falloffFractions`
      helper so a recolor never has to touch the falloff math.
      Separately, a
      shadow-casting/cone light's visibility polygon (a `shadowRayCount`
      -sided approximation of a curve, so its edges are visibly
      faceted/straight) gets a `MaskFilter.blur` on its reveal/tint
      paints, applied once per light per frame — not per sampled ray,
      so it doesn't scale with `shadowRayCount` — now driven by a new
      configurable `Light2D.shadowEdgeSoftness` (`8` default, screen-
      space, scaled by `Camera.zoom` — bumped up from an initial `3`,
      reported live as too subtle to actually read as soft against a
      typical 100–300px light radius) instead of a hardcoded constant,
      so a deliberately hazy/diffuse light can go softer and a crisp
      one can go to `0` (hard edge). All pure rendering-paint tweaks —
      no new raycasts, no per-tile cost.
- [x] Shadow flicker while the light source moves (still visible after
      the grid-raycast tie-break fix — reported live as "very very
      noisy"): new opt-in `Light2D.shadowSmoothingSeconds` (`0` default,
      off) exponentially smooths each sampled ray's raycast distance
      toward its raw value over that many seconds instead of snapping
      to it every frame, via a real per-ray cache
      (`Light2D.smoothedShadowDistances`, deliberately excluded from
      `toJson`/`fromJson` — derived render state, not anything worth
      persisting). A light moving continuously re-raycasts from scratch
      every frame, and as it crosses a tile boundary some rays' hit
      tile (and so distance) can change in a small discrete jump rather
      than smoothly — smoothing turns that jump into a brief transition
      instead of a visible pop. Framerate-independent (`1 - e^(-dt/tau)`,
      using the real wall-clock frame `dt`, newly threaded from
      `_EngineViewState._onTick` into `_EnginePainter` as
      `frameDtSeconds` — not the simulation's own tick rate, which can
      differ). Verified: new widget tests in `light2d_test.dart` drive
      `EngineView`'s real `Ticker` with explicit frame durations via
      `tester.pump` and assert `Light2D.smoothedShadowDistances`
      directly — a ray toward a solid wall stays close to the initial
      radius after one frame (proving real lag with a large `tau`) and
      converges close to the true raycast distance after many frames
      (proving it actually converges, not just lags forever);
      `shadowSmoothingSeconds: 0` confirmed to leave the cache unused
      entirely (no smoothing overhead when disabled). **Follow-up,
      reported live**: this made a moving light's shadow visibly *lag*/
      transition instead of snapping instantly to the correct geometry
      — read as "animating instead of casting real," a fair complaint:
      real light has zero transition delay, shadows should be exactly
      correct every single frame. `shadowSmoothingSeconds` stays
      available (still opt-in, still `0`/off by default) for a game
      that deliberately wants that softened look, but `test_game`'s
      player light no longer sets it — the tie-break fix above is the
      actual, correct fix for the flicker; smoothing was the wrong
      tool for that job.
- [x] Frame-rate cap: new `EngineView.maxFps`/`GameConfig.maxFps`
      (`null` default, uncapped — runs at whatever the platform's raw
      display callback delivers, same as before). A ticker callback
      arriving sooner than `1 / maxFps` since the last *processed* one
      is skipped outright (no world step, no repaint — a ceiling on
      frequency, not a guaranteed rate on a slower device that can't
      reach it). Verified: 3 new widget tests in `fixed_timestep_test.dart`
      asserting `world.tick` directly — uncapped steps on every frame
      of a fast (~120fps) burst; capped at `maxFps: 60` steps
      meaningfully fewer times than the same burst; frames already
      slower than the cap are never throttled. New `game_config_test.dart`
      coverage for `maxFps`'s round-trip and its omitted-when-null
      `toJson` shape. Full `engine_flutter` suite (211 tests) green,
      `--fatal-infos` analyze clean.
- [x] `maxFps`'s cap read as jittery, not a clean rate — reported live
      ("fps is not solid 60 why?"). Root cause: the throttle compared
      each raw callback against the *last processed* callback's own
      timestamp; on a 90Hz/120Hz display capped to 60fps (not an exact
      multiple), successive real frame gaps alternate (~11ms then
      ~22ms) even though the long-run average is genuinely 60fps.
      Fixed by scheduling against a virtual clock that advances by a
      fixed `1 / maxFps` every processed frame instead of re-anchoring
      to a jittery raw timestamp; a stall resyncs to now rather than
      bursting through backlog. `test_game`'s `maxFps` also raised to
      `120` per the same feedback. Verified: new regression test in
      `fixed_timestep_test.dart` simulating 90Hz raw callbacks and
      asserting every processed `dt` stays within 6ms of the 60fps
      target — a skip-based scheme fails this by alternating gaps.
- [x] Z-aware lighting — reported live ("if light emitted from
      character z-index and not in z-index of that object why it
      should affect it? add z-order to light emissions and shadow").
      Scoped via `AskUserQuestion` to a per-light z-range (not full
      per-object relighting, which the user didn't choose — that
      option would cost real performance they've said matters as much
      as light quality). New opt-in `Light2D.minZIndex`/`maxZIndex`
      (both `null` default — no restriction, identical to the original
      full-screen-affects-everything behavior at no extra render cost).
      `EngineView` implements this by splitting the z-sorted draw list
      into bands at every light's z boundary and compositing each
      band's darkness/reveal pass in isolation (`saveLayer`/`restore`
      per band) before the next band draws on top. Real bug caught
      only by a genuine pixel-sampling test, not the usual "renders
      without crashing" pattern this area otherwise relies on: each
      band's darkness rect was unconditionally full-screen, so a
      *later*, unlit band silently painted solid black over the
      *entire* already-composited canvas, erasing every earlier band's
      revealed content — fixed by compositing a banded darkness pass
      with `BlendMode.srcATop` (only darkens pixels that band already
      drew) instead of the default `srcOver`. Verified: new
      `Light2D.minZIndex`/`maxZIndex` round-trip test; a real
      pixel-sampling `EngineView` widget test (captures the rendered
      frame via `RenderRepaintBoundary.toImage`, samples actual pixel
      colors) proving a zIndex-0-scoped light reveals a zIndex-0 sprite
      while a zIndex-1 sprite outside its range stays dark — this is
      what caught the `srcATop` bug above; a plain "doesn't crash" test
      would have missed it entirely. Full `engine_flutter` suite (232
      tests) green, `--fatal-infos` analyze clean.
- [x] GPU-shader shadow casting — reported live (a real Android device
      showed fps dropping to ~24 with a flickering, shadow-casting
      torch in camera view). Researched how other engines handle 2D
      dynamic shadow casting at scale: the standard technique is a
      GPU-based 1D polar shadow map (occluders rendered to an offscreen
      texture, unwrapped per-angle, sampled in a lighting shader) — a
      genuine ground-up rewrite with real cross-platform risk (no way
      to test iOS from this environment, known Flutter web
      fragment-shader gaps). Implemented a scoped-down, real variant
      instead: new `Light2D.useGpuShadows` (`false` default) draws a
      GPU-shader point light (`shaders/light_shadow.frag`) doing
      per-pixel ray-vs-line-segment occlusion tests against nearby
      solid `TileMap` boundary edges (up to 32, nearest-first) — real
      parallel GPU work replacing the sequential CPU `raycastTileMap`
      sweep for that light entirely (not additional work on top of
      it). The CPU darkness-reveal/tint pass still runs for a
      GPU-shadow light, but as a plain circle/cone (cheap) rather than
      a duplicated raycast sweep; the GPU pass then draws the real
      shadow-shaped light additively on top. A real, reproducible-
      looking bug (an oversaturated/blown-out render with multiple
      simultaneous GPU-shadow lights) turned out, after isolating it
      with a minimal repro, to be a stale Flutter dev-server reload
      artifact (a `main.dart.js` MIME-type error caught mid-session
      confirms the dev server was intermittently serving stale JS) —
      re-tested on a confirmed-clean server with the exact same
      "failing" configuration (all shadow-casting lights across both
      `test_game` levels on the GPU path simultaneously) and it
      rendered correctly, 120fps, both levels, no artifacts. `flutter
      test` cannot compile/bundle a `shaders:` asset in this sandbox
      (confirmed: `flutter pub get` itself fails here on an unrelated
      dependency needing pub.dev network access) — the one pixel-
      sampling test that needs the real compiled shader skips
      gracefully with a clear reason instead of false-failing;
      verified for real via the actual web app in this session's
      browser tool instead. Full `engine_flutter` suite and
      `--fatal-infos` analyze clean. Wired into `test_game` itself
      (gitignored sample) — every shadow-casting light in both levels
      now sets `useGpuShadows: true`, confirmed rendering correctly
      (proper shadow shapes, soft falloff, no artifacts) in the
      browser at 120fps across both levels simultaneously. Still
      genuinely experimental beyond this — verified in this session's
      web/CanvasKit environment only, not on a real Android/iOS device
      (see the doc comment's own platform-risk note). **Follow-up
      idea, not started**:
      a single multi-light shader pass (all lights' data as uniform
      arrays, one draw call instead of one per light) would be a
      genuine further win — fewer GPU dispatches, and it would let a
      shader-lit scene properly composite multiple overlapping lights
      instead of relying on repeated additive passes — but is a
      meaningfully bigger rewrite than this session's scope; revisit
      if `useGpuShadows` sees real use and its current one-draw-per-
      light cost becomes the next bottleneck.
## New engine features (round 2) — Platformer (`engine_platformer`)

- [x] Ladders/climbing, conveyors, per-tile friction: `TileMap` gained
      `ladderTileIds` (plain overlap marker, `engine_core`, same
      genre-general-data reasoning as every other `*TileIds` set),
      `conveyorSpeedByTileId` (px/s nudge to `Position.x` while resolved
      grounded on that tile id), and `frictionByTileId` (multiplier on
      how fast grounded velocity snaps to the input target — missing
      entry, the default, means `1.0`/instant-snap, unchanged). New
      `engine_platformer` `LadderSystem` (opt-in via
      `PlatformerController.climbSpeed`, `0` default disables it, same
      convention as `wallJumpPushSpeed`) reads `onLadder` (set by
      `TileCollisionSystem`, reset by `PlatformerSystem` alongside
      `grounded`) and up/down input to override `Velocity.y`, run last
      in `installPlatformerSystems` so it has final say over gravity/
      jump that tick. `PlatformerInputSystem` blends toward the input
      target instead of snapping when `groundFriction < 1.0` (icy
      tiles slide); `TileCollisionSystem` applies conveyor/friction only
      on the tile actually landed on this tick, alongside the existing
      solid/one-way/slope branches. All additive/opt-in — a level with
      no tagged tiles behaves exactly as before (proven by the full
      pre-existing suite passing unchanged). Verified: new tests in
      `engine_core`'s `tile_map_test.dart` (round-trip + defaults) and
      `engine_platformer`'s `tile_collision_test.dart` (ladder overlap
      set/reset, conveyor nudges `Position.x` while grounded, friction
      sets/defaults `groundFriction`) and new `ladder_friction_test.dart`
      (friction blending vs. snap, grounded-only, `LadderSystem`'s
      climb/hold/no-op/not-on-ladder behavior) — `flutter test`/
      `dart test` and `--fatal-infos` analyze clean across all three
      packages. Live in `test_game`: added a small ladder column, an
      icy ground patch, and a conveyor ground patch to
      `main.level.json` near the spawn — the level loads and renders
      correctly with the new tile ids/legend entries (no crash, no
      console error), confirming `TileMap.fromJson`'s new fields
      round-trip through the human-authorable legend form correctly;
      actually walking onto them to see the climb/slide/push in motion
      hit the same simulated-keyboard-hold limitation noted earlier in
      this project's session history (arrow-key presses via the browser
      tool don't reliably sustain held movement) — not attempted to
      fake, the physics itself is covered by the unit tests above
      instead.
- [x] Steering/avoidance among multiple AI: new `AvoidanceBehavior`, a
      decorator around any existing `Behavior`
      (`AvoidanceBehavior(PatrolBehavior(...))`) that blends in a
      horizontal separation push away from nearby `AIState`-carrying
      entities (not literally everything within range — the player, a
      coin, a projectile are left alone) on top of whatever the wrapped
      behavior decides, rather than overriding it outright. A decorator
      rather than logic added to each of `PatrolBehavior`/
      `FollowBehavior`/`PathFollowBehavior` individually, since all
      three would otherwise need the identical nearby-entity scan and
      push-apart math duplicated three times. Uses
      `WorldView.entitiesWithinRadius` (added earlier this round).
      Verified: new `avoidance_behavior_test.dart` — two overlapping
      patrol entities end up with different velocities (one pushed
      back, one pushed further forward) rather than the identical
      velocity `PatrolBehavior` alone would give both; a nearby
      `AIState`-less entity (standing in for the player) causes no
      push at all; no push beyond `avoidRadius`; delegates cleanly when
      the wrapped behavior itself has nothing to do. Full
      `engine_platformer` suite (167 tests) green, `--fatal-infos`
      analyze clean. Wired into both of `test_game`'s existing
      patrollers (`AvoidanceBehavior(PatrolBehavior(...))`) — harmless
      as shipped, since their patrol bands don't currently overlap
      (different platform tiers), but exercised directly: a temporary
      third patroller spawned on top of the first (same band, same
      behavior) loaded and ran with no crash/console error, confirming
      the wiring itself (`spawnEnemy` + `AvoidanceBehavior` +
      `AISystem`) works end to end in a real scene; watching the
      actual separation happen live hit the same simulated-input
      limitation noted elsewhere in this file, so the precise push-
      apart math is what the unit tests above assert directly instead.
- [x] Ledge grab / mantle: new `PlatformerController.ledgeGrabEnabled`
      (`false` default, opt-in) + new `LedgeGrabSystem`. Detection is a
      tile-grid approximation in the same spirit as
      `resolveSlopeCircleAabb`'s "walkable surface, not true polygon
      physics": while airborne and touching a wall
      (`touchingWallLeft`/`touchingWallRight`, already resolved by
      `PlatformerSystem`/`TileCollisionSystem`), the tile beside the
      entity in the wall's direction must be solid at the entity's own
      row (the wall being touched), the tile one row above that must be
      empty (open headroom — this is what makes it specifically the
      wall's *top edge*, not an arbitrary point up a tall wall), and
      the tile directly above the entity's own row must be empty too
      (room for the entity's own head once it climbs up). On grab,
      `Velocity` freezes to `(0, 0)` every tick (overriding gravity/
      input — no sideways movement while hanging) until the player
      mantles (hold up/jump — teleports to a target position/one tile
      up, half a tile forward, precomputed once at grab time from the
      tile geometry that triggered it) or drops (hold down, releasing
      the grab and letting gravity resume). Runs after `JumpSystem`/
      `LadderSystem` so a jump input that also satisfies the grab
      condition results in a grab, not a jump — grabbing always takes
      priority. A knockback hit (`hitstunSeconds > 0`) releases an
      active grab outright rather than leaving the entity frozen
      mid-air while being knocked back. Verified: 10 new tests in
      `ledge_grab_system_test.dart` — grabs and freezes velocity at the
      correct snapped position; does *not* grab while grounded, without
      headroom above the wall (a tall solid face is not an edge),
      or without headroom above the entity itself; mantles correctly on
      both `up` and `jump` input, teleporting to the precomputed target
      and standing grounded; drops on `down` input without
      repositioning or touching velocity; keeps freezing velocity every
      tick while just hanging; and releases the grab on hitstun without
      re-freezing the resulting knockback velocity.
      `ledgeGrabEnabled: false` (the default) is a confirmed no-op even
      at an otherwise-grabbable position. Full `engine_platformer`
      suite (177 tests) green, `--fatal-infos` analyze clean. Also
      brought the package `README.md` up to date in the same pass — a
      new "Movement feel" section documents every
      `PlatformerController` opt-in field (several of which, like
      `coyoteTimeSeconds`/`wallJumpPushSpeed`/`jumpCutMultiplier`/
      `climbSpeed`, had never been documented in the README at all
      despite shipping in earlier rounds), a new "Tile-based terrain
      features" section covers ladders/conveyors/friction, the
      Behaviors section now lists `PathFollowBehavior`/
      `AvoidanceBehavior`, the system-order code block now matches
      `system_pack.dart` exactly (it was missing `DashSystem`,
      `LadderSystem`, `HitstunSystem`, `HealthHudSystem`,
      `ProjectileSystem`, and `AnimationTransitionSystem` — five
      previously undocumented systems), and the Damage/health/combat
      section now documents `damageEntity`/`dealDamageOnTouch`'s
      `knockbackSpeed`/`hitstunSeconds`/`source` parameters.
- [x] Swimming / water physics: new `WaterZone` component (rect,
      `Position`-is-the-center like `PlatformBody`) + new
      `WaterPhysicsSystem`, wired into `installPlatformerSystems` right
      after `TileCollisionSystem` and before `JumpSystem`. While a
      `PlatformerController` entity's collider overlaps a `WaterZone`,
      `controller.inWater` is `true` (a genuine swim state, not a
      walk/jump variant) and `Velocity.y` is buoyancy-capped to
      `WaterZone.maxFallSpeed` — corrects the *result* of this tick's
      already-applied gravity rather than needing to know
      `GravitySystem`'s configured strength, so it works regardless of
      a game's own gravity value. A `jumpRequested` press while
      submerged becomes a repeatable upward "stroke"
      (`WaterZone.swimUpSpeed`) instead of a single jump arc —
      `WaterPhysicsSystem` consumes `jumpRequested` itself so
      `JumpSystem` right after it doesn't also try to jump with the
      same press. Verified: 10 new `water_physics_test.dart` tests
      (`WaterZone`/`inWater` JSON round-trips and defaults; untouched
      outside any zone; fall speed clamped/left-alone above/below the
      cap; a stroke applies and consumes `jumpRequested`; repeated
      presses give repeated strokes, not one arc; missing-component
      entity skipped gracefully; a world with no `WaterZone` at all is
      a no-op) plus one real end-to-end test — a player entity with a
      live `Gravity` component run through 30 real ticks of
      `installPlatformerSystems`'s actual system order, confirming
      `Velocity.y` stays buoyancy-capped rather than accelerating past
      it the way plain gravity would over that many ticks. Full
      `engine_platformer`/`engine_flutter` suites and `--fatal-infos`
      analyze clean.
- [x] Boss/enemy phase framework: new `BossPhase`/`BossPhaseSystem`
      (`engine_platformer`) ties `CinematicSystem` and `Health`
      together for exactly this gap. `BossPhase(healthFraction,
      patternId, cinematicSteps)` — `patternId` is opaque to the engine
      (a game reads it off the new `BossPhaseChangedEvent` to switch
      its own AI/attack pattern, same "reference by id, game owns the
      meaning" convention `AIState`/`TriggerZone` already use);
      `cinematicSteps` is a **factory**, not a list, since a
      `CinematicStep` holds its own mutable progress and can't replay
      once consumed. `BossPhaseSystem(entity, phases)` — phases given
      in descending `healthFraction` order (validated in the
      constructor, throws otherwise) — watches
      `Health.current/Health.max` each tick; the tick it first drops
      to/below a not-yet-triggered phase's threshold, emits
      `BossPhaseChangedEvent` and, if that phase has `cinematicSteps`,
      starts playing it via an internal `CinematicSystem` instance
      driven directly from `BossPhaseSystem.update` — not registered
      on `World` itself, so a boss fight's cutscene beats don't need a
      separate system add/remove dance as they start and finish. A
      phase never re-fires once triggered, even if healing brings
      health back up and down again; a single hit crossing multiple
      thresholds at once fires every crossed phase's event in order
      (only the last one's cinematic, if any, actually plays — an
      earlier phase's beat is skipped rather than queued). Deliberately
      not an ECS `Component`/JSON-serializable (same as
      `CinematicSystem` itself isn't) — a `CinematicStep` can carry
      Dart closures (`CallbackStep`, `TweenStep.onUpdate`), so boss
      fight scripting is Dart-code-configured, not level-JSON-authored,
      consistent with how every other cinematic beat in this engine
      already works. Verified: 10 new `boss_phase_system_test.dart`
      tests (descending-order validation including ties; no-op above
      every threshold; fires exactly at a threshold; never re-fires
      after healing back up; multiple phases fire in order across
      separate ticks; a single hit crossing multiple thresholds fires
      every one in order; missing-`Health` no-op; a phase with no
      `cinematicSteps` leaves `isInCinematic` false; a phase with
      `cinematicSteps` actually plays it end-to-end through real
      `world.step` ticks, `isInCinematic` true until the `WaitStep`
      genuinely completes). Full `engine_platformer` suite and
      `--fatal-infos` analyze clean.
