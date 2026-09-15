/// Real, on-device wall-clock timing for the most recently rendered
/// `EngineView` frame — how many milliseconds `world.step()`, the full
/// paint pass, and the lighting pass alone each actually took. Exists
/// because this engine's own dev/CI environment has no access to a
/// real device's GPU/CPU profiler: when a performance question can
/// only be answered by *the actual device it was reported on*, reading
/// these numbers straight off `EngineView.showFpsOverlay`'s debug
/// readout (or via [EngineView.frameStats] for a game that wants to
/// log/export them itself) is the fastest way to find out where a
/// frame's time is actually going, without needing external tooling.
///
/// Reflects the *previous* rendered frame, one frame of lag — the same
/// timing/setState ordering `EngineView`'s existing fps counter already
/// has, since a frame's own paint pass hasn't run yet at the point its
/// widget tree is built.
class FrameStats {
  /// Milliseconds the most recent `world.step()` call(s) took —
  /// fixed-timestep mode can run more than one step in a single
  /// rendered frame; this is their combined total.
  double stepMs = 0;

  /// Milliseconds the most recent `EngineView` paint pass took, start
  /// to finish (tile/sprite/particle collection, sorting, drawing,
  /// lighting -- everything in one `CustomPainter.paint` call).
  double paintMs = 0;

  /// Milliseconds `_drawLighting` alone took within [paintMs] — broken
  /// out separately since shadow-casting/lighting is the single most
  /// expensive per-frame render cost this engine has, and has been the
  /// direct subject of more than one live performance investigation.
  double lightingMs = 0;

  /// Milliseconds between this and the previous *raw* ticker callback —
  /// the actual, unsmoothed frame interval (unlike
  /// `EngineView.showFpsOverlay`'s `fps` line, which averages over the
  /// last 30 frames and so lags/smooths out a real spike). A frame
  /// costing far more than [stepMs] + [paintMs] combined points at
  /// something *outside* this engine's own step/paint — platform
  /// input handling, GC, another widget's build/layout, the OS itself.
  double frameMs = 0;

  /// Live entity/sprite/particle counts at the moment this frame was
  /// captured — the same numbers `showFpsOverlay`'s readout already
  /// shows, mirrored here so a game logging just this object doesn't
  /// need separate `World` access to correlate scene size with timing.
  int entities = 0;
  int sprites = 0;
  int particles = 0;

  /// Speed (world px/s) of `EngineView.cameraFollowEntity`'s `Velocity`
  /// at the moment this frame was captured, or `null` if there's no
  /// followed entity, it has no `Velocity`, or `EngineView` isn't
  /// registered with `engine_core`'s core components (no `Velocity`
  /// store to read at all). Exists specifically to answer "was the
  /// player actually moving during this logged frame" from the log
  /// alone, without needing to correlate it against a separate
  /// screen recording — came up directly investigating a real
  /// fps-while-moving report where confirming genuine movement
  /// happened at all was itself a real obstacle.
  double? followedSpeed;

  /// Called synchronously, once per tick, the instant [frameMs] exceeds
  /// [spikeThresholdMs] — `this` is passed so the callback can read
  /// every field above without keeping its own reference. `null`
  /// (default) means no callback, at no per-frame cost beyond the one
  /// comparison already needed to check the threshold.
  ///
  /// Exists because the natural way to log [FrameStats] (a periodic
  /// `Timer`, printing whatever the values happen to be right then) can
  /// only ever sample — a spike lasting one or two frames between two
  /// samples is invisible to it entirely. A real fps-while-moving
  /// investigation hit exactly this: a 2-second-interval timer showed
  /// nothing but clean frames while the game visibly lagged, because
  /// every actual spike happened to land between two samples. Wiring
  /// [onSpike] instead catches every single frame that crosses the
  /// threshold, with zero sampling gap — `EngineView` calls it directly
  /// from the same tick that computes [frameMs], before any `Timer` (or
  /// even `setState`) would have run at all.
  void Function(FrameStats stats)? onSpike;

  /// [frameMs] above which [onSpike] fires. `20` by default — double a
  /// healthy 60fps frame (16.67ms), chosen from a real investigation as
  /// a threshold that reliably separates "a normal frame with a little
  /// jitter" from "an actual dropped-frame-class spike," without firing
  /// on harmless noise. Lower it for a more sensitive catch (e.g. on a
  /// 120Hz target, where even one missed vsync is only ~8ms); raise it
  /// to only catch more severe stalls.
  double spikeThresholdMs = 20;

  @override
  String toString() => 'frame: ${frameMs.toStringAsFixed(2)}ms  '
      'step: ${stepMs.toStringAsFixed(2)}ms  '
      'paint: ${paintMs.toStringAsFixed(2)}ms  '
      'light: ${lightingMs.toStringAsFixed(2)}ms  '
      'entities: $entities  sprites: $sprites  particles: $particles  '
      'speed: ${followedSpeed == null ? 'n/a' : followedSpeed!.toStringAsFixed(1)}';
}
