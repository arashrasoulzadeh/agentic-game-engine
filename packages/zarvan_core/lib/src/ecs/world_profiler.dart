import 'ring_buffer.dart';

/// Timing for one system across the sampled steps.
class SystemTiming {
  final String name;

  /// Milliseconds the system took on the most recent step.
  double lastMs = 0;

  /// Exponential moving average (see [WorldProfiler.smoothing]); steadier than
  /// [lastMs] for a readout, still reacts within a few steps.
  double averageMs = 0;

  /// Slowest single step seen since the last [WorldProfiler.reset].
  double maxMs = 0;

  int samples = 0;

  SystemTiming(this.name);

  void _record(double ms, double smoothing) {
    lastMs = ms;
    averageMs = samples == 0 ? ms : averageMs + (ms - averageMs) * smoothing;
    if (ms > maxMs) maxMs = ms;
    samples++;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'lastMs': lastMs,
    'averageMs': averageMs,
    'maxMs': maxMs,
    'samples': samples,
  };
}

/// Opt-in per-system timing for a `World`: set `world.profiler =
/// WorldProfiler()` and every `World.step` records how long each system, the
/// event flush, and the whole step took.
///
/// Costs nothing when unset (`World.step` takes the untimed path), so it can
/// stay wired in during development and be dropped for release. Timings come
/// from `Stopwatch` ticks and are *wall time on the simulation thread*: they
/// include anything the OS interrupts, so look at [SystemTiming.averageMs]
/// rather than a single sample.
class WorldProfiler {
  /// Weight of the newest sample in [SystemTiming.averageMs] (0..1].
  final double smoothing;

  final Map<String, SystemTiming> _systems = {};

  /// Recent whole-step durations in ms, for a frame-time graph.
  final RingBuffer<double> stepHistory;

  /// Time spent in `EventBus.flush` on the last step.
  double eventsMs = 0;

  /// Duration of the last whole step.
  double stepMs = 0;

  /// Entities alive at the end of the last step.
  int entityCount = 0;

  /// Number of steps recorded since the last [reset].
  int steps = 0;

  WorldProfiler({this.smoothing = 0.1, int historyLength = 120})
    : assert(smoothing > 0 && smoothing <= 1, 'smoothing must be in (0, 1]'),
      stepHistory = RingBuffer<double>(historyLength);

  /// Called by `World.step`.
  void recordSystem(String name, double ms) =>
      (_systems[name] ??= SystemTiming(name))._record(ms, smoothing);

  /// Called by `World.step` once per step.
  void recordStep({
    required double stepMs,
    required double eventsMs,
    required int entities,
  }) {
    this.stepMs = stepMs;
    this.eventsMs = eventsMs;
    entityCount = entities;
    stepHistory.add(stepMs);
    steps++;
  }

  /// Every system seen so far, slowest average first -- the "what should I
  /// optimise" order.
  List<SystemTiming> report() =>
      _systems.values.toList()
        ..sort((a, b) => b.averageMs.compareTo(a.averageMs));

  /// Share of the last step's time each system took (0..1), by name. Systems
  /// don't sum to exactly 1: the remainder is event flushing and loop overhead.
  Map<String, double> shares() {
    if (stepMs <= 0) return {for (final k in _systems.keys) k: 0};
    return {for (final t in _systems.values) t.name: t.lastMs / stepMs};
  }

  void reset() {
    _systems.clear();
    stepHistory.clear();
    eventsMs = 0;
    stepMs = 0;
    entityCount = 0;
    steps = 0;
  }

  Map<String, dynamic> toJson() => {
    'steps': steps,
    'stepMs': stepMs,
    'eventsMs': eventsMs,
    'entities': entityCount,
    'systems': [for (final t in report()) t.toJson()],
  };

  /// A fixed-width table for a log line or test failure message.
  String format() {
    final rows = report();
    final width = rows.fold<int>(
      6,
      (w, t) => t.name.length > w ? t.name.length : w,
    );
    final b = StringBuffer(
      'step ${stepMs.toStringAsFixed(3)}ms  events ${eventsMs.toStringAsFixed(3)}ms  '
      'entities $entityCount\n',
    );
    for (final t in rows) {
      b.writeln(
        '${t.name.padRight(width)}  avg ${t.averageMs.toStringAsFixed(3)}ms  '
        'max ${t.maxMs.toStringAsFixed(3)}ms',
      );
    }
    return b.toString().trimRight();
  }
}
