# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered.

Everything completed has been cleared from this file — see
[CHANGELOG.md](CHANGELOG.md) for what shipped and git history for the
full why behind each change.

## Features

- [ ] Publish `engine_core`/`engine_flutter`/`engine_cli` to pub.dev —
      removes the git-ref-matching constraint entirely via normal semver
- [ ] Test on a real Android/iOS device — **further progress**:
      `flutter build apk --release --no-pub` for `test_game` succeeded
      against a physically connected Android device (`SM S731B`,
      Android 16, found via `flutter devices`), and this session went
      further — real installs, launches, and on-device gameplay/
      profiling runs against that same device across multiple builds.
      `flutter build ios --release --no-codesign` still fails on this
      environment's broken CocoaPods (Ruby/CocoaPods version mismatch)
      — a local sandbox issue, not an engine bug, not attempted to fix
      here since it'd mean touching system Ruby/CocoaPods outside this
      repo's scope; the iOS Simulator control tool available in this
      environment is moot while the iOS build itself won't compile here
      regardless.
## Performance

- [ ] Avoid `saveLayer`+`dstOut` for the ambient-lighting overlay
      entirely — the current technique forces an offscreen render-
      target allocation and composite every single frame the pass
      runs, regardless of scene complexity; a shader-based single-pass
      approach (computing ambient darkening + light reveal directly, no
      offscreen layer) would avoid that cost structurally, but is a
      real rewrite with real cross-platform risk (this repo's own
      `useGpuShadows` investigation already found real, unresolved
      device-specific bugs going down the shader-lighting path — see
      "GPU-shader shadow casting" below; don't retrace that without
      learning from it). Considered and rejected: naively shrinking
      `saveLayer`'s bounds to just the union of active lights' circles
      instead of the full viewport — this breaks correctness, since the
      ambient wash needs full-screen coverage (anywhere not reveal-lit
      still needs the ambient-dark tone; a region clipped out of the
      layer would render at full, undarkened brightness — a real visual
      bug, not a valid shortcut). Also worth separately testing: whether
      GPU clock throttling under sustained load (one test device hit
      39.1°C on its SKIN thermal sensor, right at that hardware's
      documented "light throttling" threshold) is compounding the
      remaining baseline cost — let the device cool fully between test
      runs, or test on a second/different device, to separate "inherent
      per-frame GPU cost" from "thermal throttling on top of it."
      Real on-device profiling tools now exist for this investigation:
      `FrameStats.onSpike`/`spikeThresholdMs` (fires the instant a frame
      exceeds a threshold, zero sampling gap) and
      `EngineView.showPerformanceOverlay`/`GameConfig.showPerformanceOverlay`
      (Flutter's own raster-thread/UI-thread bar-graph widget, one flag
      instead of a custom VM-service script) — plus connecting Flutter
      DevTools' VM service directly via a small Python script
      (`websocket-client`, `setVMTimelineFlags`/`clearVMTimeline`/
      `getVMTimeline` over its WebSocket JSON-RPC) for a full raster-
      thread timeline when the overlay's live numbers alone aren't
      enough — this combination is what found `shadowEdgeSoftness`
      (see CHANGELOG) as the previous dominant cost; use it again here.
- [ ] GPU-shader shadow casting — **landed as opt-in engine
      infrastructure, but has a confirmed, unresolved real-device bug —
      NOT safe to enable, `test_game` does not use it.** Reported live
      (a real Android device showed fps dropping to ~24 with a
      flickering, shadow-casting torch in camera view). Researched how
      other engines handle 2D dynamic shadow casting at scale (a GPU-
      based 1D polar shadow map is the standard technique — a genuine
      ground-up rewrite with real cross-platform risk). Implemented a
      scoped-down variant instead: `Light2D.useGpuShadows` (`false`
      default) draws a GPU-shader point light
      (`shaders/light_shadow.frag`) doing per-pixel ray-vs-line-segment
      occlusion tests against nearby solid `TileMap` boundary edges,
      replacing the CPU `raycastTileMap` sweep for that light entirely.
      **What actually happened** (kept so the false leads aren't
      retraced): verified correct with a single light in a browser
      tool; wiring it into every `test_game` light produced an
      oversaturated white blob — first suspected (wrongly) as a stale
      dev-server artifact, since a fresh dev-server restart rendered
      correctly; shipped on that basis; then a real **release APK** (no
      dev server involved at all) reproduced the identical bug
      immediately and reliably, conclusively ruling out "just a stale
      dev server." Reverted `test_game`'s lights to `useGpuShadows:
      false` and confirmed via a fresh release-APK install that this
      restores correct rendering. **Root cause not yet confirmed on
      device, but a concrete, mechanistically-explained hypothesis now
      exists** (found via code review, not yet device-verified — no
      device was connected to test it, and this sandbox cannot even
      compile/bundle the shader to check via `flutter test`, confirmed
      by `gpu_light_shader_test.dart`'s own `markTestSkipped` path):
      `light_shadow.frag`'s `falloff(t)` is *flat at full strength
      (`1.0`) out to 60% of the light's radius* (`if (t <= 0.6) return
      1.0;`), and for an untinted light the shader's output alpha at
      that plateau is `uColor.a * strength` = `1.0 * intensity` — i.e.
      a **fully opaque white disc covering the inner 60% of every
      shadow-casting light's radius**, composited with unbounded
      `BlendMode.plus` (`src + dst`, clamped only *after* summing).
      Two such opaque plateaus overlapping — trivial for
      torches spaced for a readable corridor, e.g. this repo's own
      prison level — saturates that whole overlap region to solid
      white in one draw pair, before any third light even needs to
      contribute; every additional overlapping light only grows the
      saturated area. A single light's own opaque core is fine and
      expected (matches "verified correct with a single light"); the
      bug is this plateau being large (60% of radius, not just a small
      hot center) combined with `plus` having no ceiling across
      multiple draws — categorically different from "NaN uniforms" or
      "cone lights specifically," both already ruled out. This doesn't
      affect the CPU-path tint/overbright passes the same way despite
      also using `BlendMode.plus`, since those are driven by
      `colorArgb`'s alpha / `overbrightIntensity` — values a level
      author sets deliberately low for a subtle glow — not a hardcoded
      `1.0`.
      **Candidate fix now implemented, NOT YET VERIFIED**: the GPU pass
      in `EngineView._drawLighting` switched from `BlendMode.plus`
      (unbounded: `src + dst`, clamped only *after* summing) to
      `BlendMode.screen` (`src + dst - src*dst`, mathematically bounded
      — can never exceed full white regardless of how many lights'
      draws overlap). Zero risk to ship as-is: `useGpuShadows` still
      defaults `false` and `test_game` still doesn't enable it, so
      nothing live changed — this just means the fix is immediately
      testable the next time a device is available, instead of needing
      to be written first. **Still needs real-device confirmation
      before this bug is considered resolved** — "mathematically
      bounded" rules out this *specific* saturation mechanism but
      hasn't been checked against a real screenshot A/B or GPU frame
      capture yet, and this exact TODO item already has one false-lead
      history (the stale-dev-server misdiagnosis) worth not repeating
      by declaring victory early. If confirmed: flip `useGpuShadows` on
      in `test_game`'s torches, remove the "KNOWN BUG" language from
      `Light2D.useGpuShadows`'s doc comment, and check this item off.
      If NOT fixed: the shrink-the-`falloff`-plateau alternative
      (`light_shadow.frag`'s flat region below `1.0`, or shrinking the
      `t <= 0.6` range) is still on the table, and worth trying next
      rather than reverting to `plus`. The single-multi-light-shader-
      pass idea (one draw call for every light via uniform arrays) is
      still worth doing eventually for both performance and potentially
      fixing this by construction, but shouldn't be started until this
      is actually confirmed either way.
