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
      restores correct rendering. **Root cause not yet found** — ruled
      out: cone lights specifically, light count specifically,
      degenerate/NaN uniform values. `Light2D.useGpuShadows` stays in
      the engine, default `false`, with this history preserved on the
      field's own doc comment. **Before touching this again**: get a
      real GPU/Skia frame-capture from the device rather than guessing
      further from screenshots. The single-multi-light-shader-pass idea
      (one draw call for every light via uniform arrays) is still worth
      doing eventually for both performance and potentially fixing this
      by construction, but shouldn't be started until the current bug
      is actually understood.
