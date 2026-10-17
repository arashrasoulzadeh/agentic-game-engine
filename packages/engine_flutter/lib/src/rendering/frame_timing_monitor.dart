import 'package:engine_core/engine_core.dart' show RingBuffer;
import 'package:flutter/scheduler.dart';

/// Records how long Flutter itself spends per frame: the UI thread
/// (`buildMs`, building the frame) and the raster/GPU thread (`rasterMs`,
/// turning it into pixels).
///
/// `FrameStats` can only time this engine's Dart-side work. A frame that is slow
/// because the GPU is is the bottleneck -- heavy lighting shaders, overdraw --
/// shows up *only* here, in `rasterMs`. This is also where shader work lands: a
/// first-use shader compile appears as a one-off raster spike (the usual "shader
/// jank"), which is the closest measurable thing to shader compile time from
/// Dart, since the engine exposes no compile-time hook.
class FrameTimingMonitor {
  static const int historyLength = 120;

  final RingBuffer<double> buildHistory = RingBuffer<double>(historyLength);
  final RingBuffer<double> rasterHistory = RingBuffer<double>(historyLength);

  /// Called with each frame whose raster time exceeds [jankThresholdMs].
  void Function(double rasterMs)? onJank;

  /// Raster times above this count as [jankFrames]. 16 ms is one 60 Hz frame.
  double jankThresholdMs = 16;

  int frames = 0;
  int jankFrames = 0;

  /// The slowest raster time seen since the last [reset].
  double worstRasterMs = 0;

  bool _attached = false;

  double get lastBuildMs => buildHistory.last ?? 0;
  double get lastRasterMs => rasterHistory.last ?? 0;

  /// Fraction of recorded frames that were jank (0..1).
  double get jankRatio => frames == 0 ? 0 : jankFrames / frames;

  /// Starts listening to the engine's frame timings. Idempotent.
  void attach() {
    if (_attached) return;
    SchedulerBinding.instance.addTimingsCallback(record);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    SchedulerBinding.instance.removeTimingsCallback(record);
    _attached = false;
  }

  /// Records a batch of timings (Flutter delivers them in batches). Public so
  /// tests and replays can feed it directly.
  void record(List<FrameTiming> timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds / 1000;
      final raster = t.rasterDuration.inMicroseconds / 1000;
      buildHistory.add(build);
      rasterHistory.add(raster);
      frames++;
      if (raster > worstRasterMs) worstRasterMs = raster;
      if (raster > jankThresholdMs) {
        jankFrames++;
        onJank?.call(raster);
      }
    }
  }

  void reset() {
    buildHistory.clear();
    rasterHistory.clear();
    frames = 0;
    jankFrames = 0;
    worstRasterMs = 0;
  }
}
