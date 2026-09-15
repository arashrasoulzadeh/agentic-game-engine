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

  @override
  String toString() => 'step: ${stepMs.toStringAsFixed(2)}ms  '
      'paint: ${paintMs.toStringAsFixed(2)}ms  '
      'light: ${lightingMs.toStringAsFixed(2)}ms';
}
